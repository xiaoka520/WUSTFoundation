import Foundation

public struct SecondClassTranscript: Codable, Hashable, Sendable {
    public let categories: [SecondClassCreditCategory]
    public let earnedCredits: Decimal
    public let evaluation: String
}

public struct SecondClassCreditCategory: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let requiredCredits: Decimal
    public let earnedCredits: Decimal
    public let requirements: [SecondClassCreditRequirement]
}

public struct SecondClassCreditRequirement: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case required
        case elective
    }

    public let kind: Kind
    public let requiredCredits: Decimal
    public let earnedCredits: Decimal

    public var remainingCredits: Decimal { max(0, requiredCredits - earnedCredits) }
    public var isCompleted: Bool { earnedCredits >= requiredCredits }
}

public enum SecondClassError: Error, Equatable, Sendable {
    case authenticationRequired
    case unexpectedStatusCode(Int)
    case unexpectedRedirect
    case rejected(String)
    case invalidResponse
}
