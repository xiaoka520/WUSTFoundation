import Foundation

extension WUSTLoginClient {
    public func fetchCreditProgress() async throws -> CreditProgress {
        try await withUndergraduateSession(retryOnAuthenticationFailure: Self.isCreditProgressAuthenticationFailure) { cookie, session in
            try await CreditProgressService().fetchCreditProgress(cookie: cookie, using: session)
        }
    }

    private nonisolated static func isCreditProgressAuthenticationFailure(_ error: any Error) -> Bool {
        guard let error = error as? CreditProgressError else { return false }
        return error == .authenticationRequired
    }
}
