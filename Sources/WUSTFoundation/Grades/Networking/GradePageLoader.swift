import Foundation

struct GradePageLoader {
    func fetch(_ request: URLRequest, using session: URLSession) async throws -> String {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              let finalURL = httpResponse.url, let originalURL = request.url else {
            throw GradeError.invalidResponse
        }
        if httpResponse.statusCode == 401 ||
            ["auth.wust.edu.cn", "atrust.wust.edu.cn"].contains(finalURL.host ?? "") {
            throw GradeError.authenticationRequired
        }
        guard httpResponse.statusCode == 200 else {
            throw GradeError.unexpectedStatusCode(httpResponse.statusCode)
        }
        guard finalURL.scheme == originalURL.scheme, finalURL.host == originalURL.host,
              finalURL.port == originalURL.port, finalURL.path == originalURL.path else {
            throw GradeError.unexpectedRedirect
        }
        guard let html = String(data: data, encoding: .utf8) else { throw GradeError.invalidEncoding }
        return html
    }
}
