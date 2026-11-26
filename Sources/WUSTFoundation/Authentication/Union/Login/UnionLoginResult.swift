public enum UnionLoginResult: Sendable {
    case authenticated(UnionCredential)
    case verificationRequired(UnionVerificationChallenge)
}
