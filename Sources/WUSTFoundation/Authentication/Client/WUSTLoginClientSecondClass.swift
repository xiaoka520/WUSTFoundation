import Foundation

extension WUSTLoginClient {
    public func fetchSecondClassTranscript() async throws -> SecondClassTranscript {
        try await withUnionCredentialAndSession { credential, session in
            try await SecondClassService().fetchTranscript(credential: credential, using: session)
        }
    }
}
