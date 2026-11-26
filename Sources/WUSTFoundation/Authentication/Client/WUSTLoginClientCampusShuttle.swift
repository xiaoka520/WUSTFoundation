import Foundation

extension WUSTLoginClient {
    public func fetchCampusShuttleSchedule() async throws -> CampusShuttleSchedule {
        try await withUnionCredentialAndSession { credential, session in
            try await CampusShuttleService().fetchSchedule(credential: credential, using: session)
        }
    }
}
