import Foundation

public struct TrainingPlanService: Sendable {
    public init() {}

    public func fetchTrainingPlan(cookie: String, using session: URLSession) async throws -> TrainingPlan {
        guard !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TrainingPlanError.authenticationRequired
        }
        guard let url = URL(string: "https://bkjx.wust.edu.cn/jsxsd/pyfa/topyfamx") else {
            throw TrainingPlanError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, let finalURL = httpResponse.url else {
            throw TrainingPlanError.invalidResponse
        }
        if httpResponse.statusCode == 401 ||
            ["auth.wust.edu.cn", "atrust.wust.edu.cn"].contains(finalURL.host ?? "") {
            throw TrainingPlanError.authenticationRequired
        }
        guard httpResponse.statusCode == 200 else {
            throw TrainingPlanError.unexpectedStatusCode(httpResponse.statusCode)
        }
        guard finalURL.scheme == url.scheme, finalURL.host == url.host,
              finalURL.port == url.port, finalURL.path == url.path else {
            throw TrainingPlanError.unexpectedRedirect
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw TrainingPlanError.invalidEncoding
        }
        return try TrainingPlanParser().parse(from: html)
    }
}
