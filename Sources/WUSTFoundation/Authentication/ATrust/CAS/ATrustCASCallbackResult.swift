// MARK: 对外返回的结果
public struct ATrustCASCallbackResult: Sendable {
    public let environmentTicket: String?
    public let nextService: String?
}
