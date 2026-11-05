import Foundation

public struct GradeService: Sendable {
    public init() {}

    public func fetchQueryOptions(cookie: String, using session: URLSession) async throws -> GradeQueryOptions {
        try await fetchForm(cookie: cookie, using: session).options
    }

    public func fetchGrades(
        query: GradeQuery = GradeQuery(),
        cookie: String,
        using session: URLSession
    ) async throws -> GradeReport {
        let form = try await fetchForm(cookie: cookie, using: session)
        let factory = GradeRequestFactory()
        let listURL = try factory.listURL()
        let cookies = session.configuration.httpCookieStorage?.cookies(for: listURL) ?? []
        let currentCookie = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? cookie
        let request = try factory.makeQueryRequest(query: query, form: form, cookie: currentCookie)
        let html = try await GradePageLoader().fetch(request, using: session)
        return try GradeParser().parse(from: html, query: query)
    }

    private func fetchForm(cookie: String, using session: URLSession) async throws -> GradeForm {
        guard !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GradeError.authenticationRequired
        }
        let request = try GradeRequestFactory().makeEntryRequest(cookie: cookie)
        let html = try await GradePageLoader().fetch(request, using: session)
        return try GradeFormParser().parse(from: html)
    }
}
