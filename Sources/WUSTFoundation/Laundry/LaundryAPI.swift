import Foundation

struct LaundryAPI: Sendable {
    enum Profile: Sendable {
        case iosApp
        case safari
    }

    private static let baseURL = URL(string: "https://userapi.qiekj.com/")!
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private let profile: Profile
    private let session: URLSession

    init(profile: Profile, session: URLSession? = nil) {
        self.profile = profile
        self.session = session ?? Self.defaultSession
    }

    func post<Payload: Decodable>(_ path: String, fields: [String: String]) async throws -> Payload? {
        var form = URLComponents()
        form.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let body = form.percentEncodedQuery else { throw LaundryQueryError.invalidResponse }
        let url = Self.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        switch profile {
        case .iosApp:
            request.setValue("ios_app", forHTTPHeaderField: "channel")
            request.setValue("1.28.2", forHTTPHeaderField: "Version")
            request.setValue(
                "QEUser/1.28.2 (com.qiekj.QEUser; build:2; iOS 16.5.0) Alamofire/5.6.4",
                forHTTPHeaderField: "User-Agent"
            )
        case .safari:
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
        }
        request.httpBody = Data(body.replacingOccurrences(of: "+", with: "%2B").utf8)

        let (data, response) = try await session.data(for: request, delegate: RejectLaundryRedirects())
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url == url else { throw LaundryQueryError.invalidResponse }
        guard http.statusCode == 200 else { throw LaundryQueryError.unexpectedStatusCode(http.statusCode) }
        guard let envelope = try? JSONDecoder().decode(Envelope<Payload>.self, from: data) else {
            throw LaundryQueryError.invalidResponse
        }
        guard envelope.code == 0 else { throw LaundryQueryError.rejected(envelope.code) }
        return envelope.data
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        let code: Int
        let data: Payload?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decode(Int.self, forKey: .code)
            data = code == 0 ? try container.decodeIfPresent(Payload.self, forKey: .data) : nil
        }

        private enum CodingKeys: String, CodingKey { case code, data }
    }
}

private final class RejectLaundryRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
