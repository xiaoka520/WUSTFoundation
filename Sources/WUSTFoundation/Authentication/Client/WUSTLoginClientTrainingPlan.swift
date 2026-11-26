import Foundation

extension WUSTLoginClient {
    public func fetchTrainingPlan() async throws -> TrainingPlan {
        try await withUndergraduateSession(retryOnAuthenticationFailure: Self.isTrainingPlanAuthenticationFailure) { cookie, session in
            try await TrainingPlanService().fetchTrainingPlan(cookie: cookie, using: session)
        }
    }

    private nonisolated static func isTrainingPlanAuthenticationFailure(_ error: any Error) -> Bool {
        guard let error = error as? TrainingPlanError else { return false }
        return error == .authenticationRequired
    }
}
