import Foundation

extension WUSTLoginClient {
    public func fetchCampusShuttleSchedule() async throws -> CampusShuttleSchedule {
        try await withAuthenticatedSession { session in
            try await CampusShuttleService().fetchSchedule(using: session)
        }
    }
}
