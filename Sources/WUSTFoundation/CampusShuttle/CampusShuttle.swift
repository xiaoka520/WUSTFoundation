import Foundation

public enum CampusShuttle {
    public static let scheduleURL = URL(string: "https://portal.wust.edu.cn/#/index70")!
}

public struct CampusShuttleSchedule: Codable, Hashable, Sendable {
    public let title: String
    public let departures: [CampusShuttleDeparture]
    public let notes: [String]
}

public struct CampusShuttleDeparture: Codable, Hashable, Sendable {
    public let operatingDays: String
    public let origin: String
    public let destination: String
    public let departureTime: String
    public let route: String
}

public enum CampusShuttleError: Error, Equatable, Sendable {
    case authenticationRequired
    case unexpectedStatusCode(Int)
    case rejected(Int)
    case invalidResponse
    case invalidSchedule
}
