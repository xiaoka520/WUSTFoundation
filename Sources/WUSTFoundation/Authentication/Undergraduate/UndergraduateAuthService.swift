import Foundation

public enum UndergraduateAuthServiceError: Error {
    case invalidURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case cookieMissing
    case invalidEncoding //UTF-8解码失败
    case invalidSession //html.contains("script")
    case systemUnavailable //"禁用"
    case studentRecordNotFound //"不存在"
    case remoteSystemError //"500"
}

public struct UndergraduateAuthService {

    public init() {}

    private func exchangeTicket(ticket: String, using session: URLSession) async throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "bkjx.wust.edu.cn"
        components.path = "/jsxsd/"
        components.queryItems = [
            URLQueryItem(name: "ticket", value: ticket)
        ]

        guard let ticketURL = components.url else {
            throw UndergraduateAuthServiceError.invalidURL
        }

        guard let baseURL = URL(string: "https://bkjx.wust.edu.cn/jsxsd/") else {
            throw UndergraduateAuthServiceError.invalidURL
        }
        var ticketRequest = URLRequest(url: ticketURL)
        ticketRequest.httpMethod = "GET"
        var baseRequest = URLRequest(url: baseURL)
        baseRequest.httpMethod = "GET"

        let (_, ticketResponse) = try await session.data(for: ticketRequest)
        guard let ticketHttpResponse = ticketResponse as? HTTPURLResponse else {
            throw UndergraduateAuthServiceError.invalidResponse
        }
        guard (200..<300).contains(ticketHttpResponse.statusCode) else {
            throw UndergraduateAuthServiceError
                .unexpectedStatusCode(ticketHttpResponse.statusCode)
        }

        rememberCookies(from: ticketHttpResponse, using: session)

        let (_, baseResponse) = try await session.data(for: baseRequest)
        guard let baseHttpResponse = baseResponse as? HTTPURLResponse else {
            throw UndergraduateAuthServiceError.invalidResponse
        }
        guard (200..<300).contains(baseHttpResponse.statusCode) else {
            throw UndergraduateAuthServiceError
                .unexpectedStatusCode(baseHttpResponse.statusCode)
        }

        rememberCookies(from: baseHttpResponse, using: session)
        return try await currentSessionCookie(using: session)
    }

    @available(*, deprecated, message: "Use WUSTLoginClient for login and SMS continuation, or the credential-based API.")
    public func login(
        username: String,
        password: String,
        captcha: LoginCaptcha,
        captchaCode: String,
        using session: URLSession
    ) async throws -> String {
        let service = "https://bkjx.wust.edu.cn/jsxsd/"
        let ticket = try await UnionAuthService().fetchServiceTicket(
            username: username,
            password: password,
            service: service,
            captcha: captcha,
            captchaCode: captchaCode,
            using: session
        )

        let cookie = try await exchangeTicket(ticket: ticket, using: session)
        return cookie
    }

    private func validateSession(using session: URLSession) async throws {
        guard let url = URL(string: "https://bkjx.wust.edu.cn/jsxsd/framework/blankPage.jsp") else {
            throw UndergraduateAuthServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UndergraduateAuthServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw UndergraduateAuthServiceError.unexpectedStatusCode(httpResponse.statusCode)
        }

        guard let finalURL = httpResponse.url,
              finalURL.scheme == url.scheme,
              finalURL.host == url.host,
              finalURL.path == url.path else {
            throw UndergraduateAuthServiceError.invalidSession
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw UndergraduateAuthServiceError.invalidEncoding
        }

        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        if html.contains("禁用") { throw UndergraduateAuthServiceError.systemUnavailable }
        if html.contains("不存在") { throw UndergraduateAuthServiceError.studentRecordNotFound }
        if html.contains("500") { throw UndergraduateAuthServiceError.remoteSystemError }
        if html.lowercased().contains("script") { throw UndergraduateAuthServiceError.invalidSession }
        throw UndergraduateAuthServiceError.invalidResponse

    }

    public func login(
        credential: UnionCredential,
        using session: URLSession
    ) async throws -> String {
        let service = "https://bkjx.wust.edu.cn/jsxsd/"
        let ticket = try await UnionAuthService().fetchServiceTicket(
            credential: credential,
            service: service,
            using: session
        )
        return try await exchangeTicket(
            ticket: ticket,
            using: session
        )

    }

    private func rememberCookies(from response: HTTPURLResponse, using session: URLSession) {
        guard session.configuration.httpShouldSetCookies,
              let storage = session.configuration.httpCookieStorage,
              storage.cookieAcceptPolicy != .never,
              let url = response.url else { return }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            if let key = entry.key as? String, let value = entry.value as? String { result[key] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        storage.setCookies(cookies, for: url, mainDocumentURL: url)
    }

    private func readCookie(using session: URLSession) throws -> String {
        guard let studentInfoURL = URL(string: "https://bkjx.wust.edu.cn/jsxsd/grxx/xsxx") else {
            throw UndergraduateAuthServiceError.invalidURL
        }

        guard let studentInfoCookies = session.configuration.httpCookieStorage?.cookies(
            for: studentInfoURL
        ), !studentInfoCookies.isEmpty else {
            throw UndergraduateAuthServiceError.cookieMissing
        }

        let headers = HTTPCookie.requestHeaderFields(with: studentInfoCookies)
        guard let cookie = headers["Cookie"], !cookie.isEmpty else {
            throw UndergraduateAuthServiceError.cookieMissing
        }
        return cookie
    }

    public func currentSessionCookie(
        using session: URLSession
    ) async throws -> String {
        _ = try readCookie(using: session)
        try await validateSession(using: session)
        return try readCookie(using: session)
    }
}
