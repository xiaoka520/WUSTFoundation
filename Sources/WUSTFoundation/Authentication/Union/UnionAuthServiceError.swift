public enum UnionAuthServiceError: Error {
    case invalidURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case invalidFormEncoding
    case loginFailed(String)
    case configurationRejected(Int)
    case credentialExpired
    case verificationMethodUnavailable
    case smsCodeRejected(Int)
    case smsCodeNotConfirmed
    case smsCodeRejected(Int, String)
    case smsVerificationRejected(Int, String)
    case smsVerificationNotConfirmed
}
