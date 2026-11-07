import Foundation

public struct LaundryCredential: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let userID: String
    public let firstVerifiedAt: Date
    public let lastVerifiedAt: Date
    let token: String

    public var description: String { "LaundryCredential" }
    public var debugDescription: String { description }
}
