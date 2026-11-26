import Foundation

extension WUSTLoginClient {
    public func fetchSecondClassTranscript() async throws -> SecondClassTranscript {
        try await withAuthenticatedSession { session in
            try await SecondClassService().fetchTranscript(using: session)
        }
    }
}
