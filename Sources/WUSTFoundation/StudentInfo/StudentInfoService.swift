import Foundation

public enum StudentInfoServiceError: Error {
    case invalidResponse
    case unexpectedStatusCode(Int)
    case invalidEncoding
    case invalidURL
}

public struct StudentInfoService {
    
    public init() {}
    
    func makeRequest(url: URL, cookie: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        return request
    }

    func fetchHTML(url: URL, cookie: String, using session: URLSession) async throws -> String {
        let request = makeRequest(url: url, cookie: cookie)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StudentInfoServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw StudentInfoServiceError.unexpectedStatusCode(httpResponse.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw StudentInfoServiceError.invalidEncoding
        }
        return html
    }
    
    public func fetchStudentInfo(cookie: String, using session: URLSession) async throws -> StudentInfo {
        guard let url = URL(string: "https://bkjx.wust.edu.cn/jsxsd/grxx/xsxx") else {
            throw StudentInfoServiceError.invalidURL
        }
        let html = try await fetchHTML(
            url: url,
            cookie: cookie,
            using: session
        )
        return try StudentInfoParser().parse(from: html)
    }
}
