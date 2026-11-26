import Foundation

extension WUSTLoginClient {
    public func fetchExamQueryOptions() async throws -> ExamQueryOptions {
        try await withUndergraduateSession(retryOnAuthenticationFailure: Self.isExamAuthenticationFailure) { cookie, session in
            try await ExamService().fetchQueryOptions(cookie: cookie, using: session)
        }
    }

    public func fetchExamSchedule(query: ExamQuery) async throws -> ExamSchedule {
        try await withUndergraduateSession(retryOnAuthenticationFailure: Self.isExamAuthenticationFailure) { cookie, session in
            try await ExamService().fetchExamSchedule(query: query, cookie: cookie, using: session)
        }
    }

    private nonisolated static func isExamAuthenticationFailure(_ error: any Error) -> Bool {
        guard let error = error as? ExamError else { return false }
        return error == .authenticationRequired
    }
}
