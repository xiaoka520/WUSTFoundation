import Foundation

public struct ExamService: Sendable {
    public init() {}

    public func fetchQueryOptions(cookie: String, using session: URLSession) async throws -> ExamQueryOptions {
        try await fetchForm(cookie: cookie, using: session).options
    }

    public func fetchExamSchedule(query: ExamQuery, cookie: String, using session: URLSession) async throws -> ExamSchedule {
        let form = try await fetchForm(cookie: cookie, using: session)
        let factory = ExamRequestFactory()
        let listURL = try factory.listURL()
        let cookies = session.configuration.httpCookieStorage?.cookies(for: listURL) ?? []
        let currentCookie = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? cookie
        let request = try factory.makeQueryRequest(query: query, form: form, cookie: currentCookie)
        let html = try await ExamPageLoader().fetch(request, using: session)
        return try ExamParser().parse(from: html, query: query)
    }

    private func fetchForm(cookie: String, using session: URLSession) async throws -> ExamForm {
        guard !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExamError.authenticationRequired
        }
        let request = try ExamRequestFactory().makeEntryRequest(cookie: cookie)
        let html = try await ExamPageLoader().fetch(request, using: session)
        return try ExamFormParser().parse(from: html)
    }
}
