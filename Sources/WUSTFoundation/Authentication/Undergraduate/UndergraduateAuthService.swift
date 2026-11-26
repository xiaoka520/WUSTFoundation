import Foundation

public enum UndergraduateAuthServiceError: Error, Equatable {
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
