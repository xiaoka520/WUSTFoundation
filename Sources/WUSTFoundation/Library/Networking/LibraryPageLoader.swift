import Foundation

struct LibraryPageLoader: Sendable {
    func fetch(
        _ request: URLRequest, using session: URLSession, followsRedirects: Bool = false
    ) async throws -> Data {
        let delegate: (any URLSessionTaskDelegate)? = followsRedirects ? nil : LibraryReadRedirectDelegate()
        let (data, response) = try await session.data(for: request, delegate: delegate)
        guard let httpResponse = response as? HTTPURLResponse,
              let requestedURL = request.url,
              let finalURL = httpResponse.url else {
            throw LibraryError.invalidResponse
        }
        if httpResponse.statusCode == 401 ||
            (!followsRedirects && httpResponse.statusCode == 302) ||
            finalURL.host == "auth.wust.edu.cn" {
            throw LibraryError.authenticationRequired
        }
        guard httpResponse.statusCode == 200 else {
            throw LibraryError.unexpectedStatusCode(httpResponse.statusCode)
        }
        guard finalURL.scheme == requestedURL.scheme,
              finalURL.host == requestedURL.host,
              (finalURL.port ?? 443) == (requestedURL.port ?? 443) else {
            throw LibraryError.unexpectedRedirect
        }
        return data
    }
}

private final class LibraryReadRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
