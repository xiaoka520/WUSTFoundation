import Foundation

public struct LoginCaptcha: Decodable, Sendable {
    public let uid: String
    public let content: String
}
