import Foundation

public enum WUSTLoginResult: Sendable {
    case authenticated(cookie: String)
    case loginRequired
}

public enum WUSTLoginClientError: Error {
    case invalidConfiguration
    case operationInProgress
    case verificationNotPending
    case notAuthenticated
    case studentIDMismatch
}
