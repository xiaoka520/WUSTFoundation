import Foundation

extension WUSTLoginClient {
    public func fetchGradeQueryOptions() async throws -> GradeQueryOptions {
        try await withUndergraduateSession(retryOnAuthenticationFailure: Self.isGradeAuthenticationFailure) { cookie, session in
            try await GradeService().fetchQueryOptions(cookie: cookie, using: session)
        }
    }

    public func fetchGrades(query: GradeQuery = GradeQuery()) async throws -> GradeReport {
        try await withUndergraduateSession(retryOnAuthenticationFailure: Self.isGradeAuthenticationFailure) { cookie, session in
            try await GradeService().fetchGrades(query: query, cookie: cookie, using: session)
        }
    }

    private nonisolated static func isGradeAuthenticationFailure(_ error: any Error) -> Bool {
        guard let error = error as? GradeError else { return false }
        return error == .authenticationRequired
    }
}
