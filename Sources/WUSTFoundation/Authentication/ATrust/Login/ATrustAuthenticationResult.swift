import Foundation

public struct ATrustAuthenticationResult: Sendable {
    public let sidTicket: String?
    public let nextService: String?
    public var isAuthenticated: Bool {
        if sidTicket?.isEmpty == false && nextService == ""{
            return true
        }
        return false
    }
}
