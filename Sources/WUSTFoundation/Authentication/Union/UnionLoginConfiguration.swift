import Foundation

public struct UnionLoginConfiguration: Decodable, Sendable {
    public let isVerifyCode: String
    public let captchaType: String
    public let isTwoVerify: String
    public let twoVerifyWay: String
}

struct UnionLoginConfigurationResponse: Decodable {
    let meta: UnionResponseMeta
    let data: UnionLoginConfiguration?
}

struct UnionResponseMeta: Decodable {
    let success: Bool
    let statusCode: Int
}
