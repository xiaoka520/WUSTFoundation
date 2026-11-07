import CryptoKit
import Foundation

struct CampusShuttleService: Sendable {
    private static let portalURL = URL(string: "https://portal.wust.edu.cn/")!
    private static let callbackURL = portalURL.appendingPathComponent("shiro-cas")
    private static let cardPath = "api/upp/contentDisplay/queryAppointCard/e05973ba27214e7a97234733848f05d5"

    func fetchSchedule(credential: UnionCredential, using session: URLSession) async throws -> CampusShuttleSchedule {
        do {
            return try await fetchSchedule(using: session, authorization: nil)
        } catch CampusShuttleError.authenticationRequired {
            let authorization = try await exchangeTicket(credential: credential, using: session)
            return try await fetchSchedule(using: session, authorization: authorization)
        }
    }

    private func exchangeTicket(credential: UnionCredential, using session: URLSession) async throws -> String? {
        let service = try await preparePortalLogin(using: session)
        let ticket = try await UnionAuthService().fetchServiceTicket(
            credential: credential, service: service, using: session
        )
        var components = URLComponents(url: Self.callbackURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
        let (_, response) = try await session.data(
            for: URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData),
            delegate: CampusShuttleRedirectDelegate()
        )
        guard let http = response as? HTTPURLResponse, let url = http.url,
              Self.isPortalURL(url) else { throw CampusShuttleError.invalidResponse }

        if (300..<400).contains(http.statusCode) {
            guard let location = http.value(forHTTPHeaderField: "Location"),
                  let redirect = URL(string: location, relativeTo: url)?.absoluteURL,
                  Self.isPortalURL(redirect),
                  let authorization = Self.callbackAuthorization(from: redirect) else {
                throw CampusShuttleError.authenticationRequired
            }
            return authorization
        }
        guard http.statusCode == 200 else {
            throw CampusShuttleError.unexpectedStatusCode(http.statusCode)
        }
        return Self.callbackAuthorization(from: url)
    }

    private func preparePortalLogin(using session: URLSession) async throws -> String {
        var components = URLComponents(
            url: Self.portalURL.appendingPathComponent("auth"), resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "service", value: CampusShuttle.scheduleURL.absoluteString)]
        let request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
        let (_, response) = try await session.data(
            for: request, delegate: CampusShuttleRedirectDelegate(followsRedirects: false)
        )
        guard let http = response as? HTTPURLResponse else { throw CampusShuttleError.invalidResponse }
        guard (300..<400).contains(http.statusCode) else {
            throw CampusShuttleError.unexpectedStatusCode(http.statusCode)
        }
        guard let location = http.value(forHTTPHeaderField: "Location"),
              let redirect = URLComponents(string: location),
              redirect.scheme == "https", redirect.host == "auth.wust.edu.cn",
              (redirect.port ?? 443) == 443, redirect.path == "/lyuapServer/login",
              redirect.user == nil, redirect.password == nil,
              let service = redirect.queryItems?.first(where: { $0.name == "service" })?.value,
              service == Self.callbackURL.absoluteString else {
            throw CampusShuttleError.invalidResponse
        }
        return service
    }

    private func fetchSchedule(
        using session: URLSession, authorization: String?
    ) async throws -> CampusShuttleSchedule {
        var login = makeRequest(path: "tryLoginUserInfo", method: "POST", using: session)
        login.setValue("ly-upp", forHTTPHeaderField: "gatewayAppId")
        login.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        login.setValue("https://portal.wust.edu.cn", forHTTPHeaderField: "Origin")
        login.setValue(authorization ?? "undefined", forHTTPHeaderField: "Authorization")
        let profile: PortalProfile = try await fetch(login, using: session)
        guard !profile.userID.value.isEmpty else {
            throw CampusShuttleError.authenticationRequired
        }

        var request = makeRequest(path: Self.cardPath, method: "GET", using: session)
        request.setValue(profile.accessToken ?? "null", forHTTPHeaderField: "Authorization")
        request.setValue(profile.userID.value, forHTTPHeaderField: "loginUserId")
        request.setValue(profile.userID.value, forHTTPHeaderField: "loginUserName")
        request.setValue(profile.orgID?.value, forHTTPHeaderField: "loginUserOrgId")
        request.setValue(profile.departmentID?.value, forHTTPHeaderField: "loginUserDeptId")

        let card: PortalCard = try await fetch(request, using: session)
        return try CampusShuttleParser().parse(card.contentDisplay.html)
    }

    private func makeRequest(path: String, method: String, using session: URLSession) -> URLRequest {
        var components = URLComponents(
            url: Self.portalURL.appendingPathComponent(path), resolvingAgainstBaseURL: false
        )!
        let now = Date().timeIntervalSince1970
        if method == "GET" {
            components.queryItems = [URLQueryItem(name: "_t", value: String(Int64(now)))]
        }
        let timestamp = String(Int64(now * 1000))
        let signature = Insecure.MD5.hash(data: Data("timestamp=\(timestamp),key=lianyi2019".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let url = components.url!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(Self.portalURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(timestamp, forHTTPHeaderField: "csrfTimestamp")
        request.setValue(signature, forHTTPHeaderField: "csrfToken")
        if let cookie = session.configuration.httpCookieStorage?.cookies(for: url)?
            .first(where: { $0.name == "XSRF-TOKEN" }) {
            request.setValue(cookie.value.removingPercentEncoding ?? cookie.value, forHTTPHeaderField: "X-XSRF-TOKEN")
        }
        return request
    }

    private func fetch<Value: Decodable>(_ request: URLRequest, using session: URLSession) async throws -> Value {
        let (data, response) = try await session.data(for: request, delegate: CampusShuttleRedirectDelegate(followsRedirects: false))
        guard let http = response as? HTTPURLResponse, let url = http.url,
              Self.isPortalURL(url) else { throw CampusShuttleError.invalidResponse }
        if http.statusCode == 401 || (300..<400).contains(http.statusCode) {
            throw CampusShuttleError.authenticationRequired
        }
        guard http.statusCode == 200 else {
            throw CampusShuttleError.unexpectedStatusCode(http.statusCode)
        }
        guard let envelope = try? JSONDecoder().decode(PortalResponse<Value>.self, from: data) else {
            throw CampusShuttleError.invalidResponse
        }
        if [302, 401].contains(envelope.meta.statusCode) { throw CampusShuttleError.authenticationRequired }
        guard envelope.meta.success else { throw CampusShuttleError.rejected(envelope.meta.statusCode) }
        guard let value = envelope.data else { throw CampusShuttleError.invalidResponse }
        return value
    }

    fileprivate static func isPortalURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == portalURL.host && (url.port ?? 443) == 443 &&
            url.user == nil && url.password == nil
    }

    fileprivate static func callbackAuthorization(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let fragmentQuery = components.percentEncodedFragment?.split(separator: "?", maxSplits: 1)
        let fragmentItems: [URLQueryItem]
        if let fragmentQuery, fragmentQuery.count == 2 {
            var fragment = URLComponents()
            fragment.percentEncodedQuery = String(fragmentQuery[1])
            fragmentItems = fragment.queryItems ?? []
        } else {
            fragmentItems = []
        }
        return (fragmentItems + (components.queryItems ?? []))
            .first { ["Authorization", "tokenId"].contains($0.name) && $0.value?.isEmpty == false }?.value
    }
}

private final class CampusShuttleRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let followsRedirects: Bool

    init(followsRedirects: Bool = true) {
        self.followsRedirects = followsRedirects
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard followsRedirects, let url = request.url, CampusShuttleService.isPortalURL(url),
              CampusShuttleService.callbackAuthorization(from: url) == nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private struct PortalResponse<Value: Decodable>: Decodable {
    struct Metadata: Decodable {
        let success: Bool
        let statusCode: Int
    }

    let meta: Metadata
    let data: Value?

    private enum CodingKeys: String, CodingKey { case meta, data }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meta = try container.decode(Metadata.self, forKey: .meta)
        data = meta.success ? try container.decodeIfPresent(Value.self, forKey: .data) : nil
    }
}

private struct PortalProfile: Decodable {
    let accessToken: String?
    let userID: PortalID
    let orgID: PortalID?
    let departmentID: PortalID?

    private enum CodingKeys: String, CodingKey {
        case accessToken
        case userID = "userId"
        case orgID = "orgId"
        case departmentID = "departmentId"
    }
}

private struct PortalID: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else {
            value = try String(container.decode(Int64.self))
        }
    }
}

private struct PortalCard: Decodable {
    struct ContentDisplay: Decodable {
        let html: String
    }

    let contentDisplay: ContentDisplay
}
