import Foundation


public enum WUSTLoginResult: Sendable {
    case authenticated(cookie: String)
    case loginRequired
    case verificationRequired(UnionVerificationChallenge, methods: [UnionVerificationMethod])
    case additionalAuthenticationRequired(nextService: String?)
}

public enum WUSTLoginClientError: Error {
    case invalidConfiguration
    case operationInProgress
    case verificationNotPending
    case notAuthenticated
    case captchaRecognitionExhausted
    case invalidCaptchaImage
    case studentIDMismatch
}

public protocol UnionCredentialStore: Sendable {
    func loadCredential(for username: String) async throws -> UnionCredential?
    func saveCredential(_ credential: UnionCredential, for username: String) async throws
    func clearCredential(for username: String) async throws
}
