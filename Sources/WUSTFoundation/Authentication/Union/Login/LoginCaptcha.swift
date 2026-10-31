import Foundation

public struct LoginCaptcha: Decodable {
    public let uid: String
    public let content: String
}
