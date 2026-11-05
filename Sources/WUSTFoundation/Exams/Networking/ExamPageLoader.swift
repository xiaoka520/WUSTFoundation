import Foundation

struct ExamPageLoader {
    func fetch(_ request: URLRequest, using session: URLSession) async throws -> String {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              let finalURL = httpResponse.url, let originalURL = request.url else { throw ExamError.invalidResponse }
        if httpResponse.statusCode == 401 ||
            ["auth.wust.edu.cn", "atrust.wust.edu.cn"].contains(finalURL.host ?? "") {
            throw ExamError.authenticationRequired
        }
        guard httpResponse.statusCode == 200 else { throw ExamError.unexpectedStatusCode(httpResponse.statusCode) }
        guard finalURL.scheme == originalURL.scheme, finalURL.host == originalURL.host,
              finalURL.port == originalURL.port, finalURL.path == originalURL.path else {
            throw ExamError.unexpectedRedirect
        }
        guard let html = String(data: data, encoding: .utf8) else { throw ExamError.invalidEncoding }
        return html
    }
}
