import Foundation

public struct CreditProgressService: Sendable {
    public init() {}

    public func fetchCreditProgress(cookie: String, using session: URLSession) async throws -> CreditProgress {
        guard !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CreditProgressError.authenticationRequired
        }
        guard let url = URL(string: "https://bkjx.wust.edu.cn/jsxsd/xxwcqk/xxwcqk_idxOnzh.do") else {
            throw CreditProgressError.invalidURL
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, let finalURL = response.url else {
            throw CreditProgressError.invalidResponse
        }
        if response.statusCode == 401 || ["auth.wust.edu.cn", "atrust.wust.edu.cn"].contains(finalURL.host ?? "") {
            throw CreditProgressError.authenticationRequired
        }
        guard response.statusCode == 200 else { throw CreditProgressError.unexpectedStatusCode(response.statusCode) }
        guard finalURL.scheme == url.scheme, finalURL.host == url.host,
              finalURL.port == url.port, finalURL.path == url.path else {
            throw CreditProgressError.unexpectedRedirect
        }
        guard let html = String(data: data, encoding: .utf8) else { throw CreditProgressError.invalidEncoding }
        return try CreditProgressParser().parse(from: html)
    }
}
