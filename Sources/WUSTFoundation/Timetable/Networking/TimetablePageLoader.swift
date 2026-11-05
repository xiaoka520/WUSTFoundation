import Foundation

struct TimetablePageLoader: Sendable {
    func fetch(
        _ request: URLRequest,
        using session: URLSession
    ) async throws -> (html: String, url: URL) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              let finalURL = httpResponse.url,
              let requestedURL = request.url else {
            throw TimetableError.invalidResponse
        }
        if httpResponse.statusCode == 401 ||
            ["auth.wust.edu.cn", "atrust.wust.edu.cn"].contains(finalURL.host ?? "") {
            throw TimetableError.authenticationRequired
        }
        guard httpResponse.statusCode == 200 else {
            throw TimetableError.unexpectedStatusCode(httpResponse.statusCode)
        }
        guard finalURL.scheme == requestedURL.scheme,
              finalURL.host == requestedURL.host,
              finalURL.port == requestedURL.port,
              finalURL.path == requestedURL.path else {
            throw TimetableError.unexpectedRedirect
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw TimetableError.invalidEncoding
        }
        return (html: html, url: finalURL)
    }
}
