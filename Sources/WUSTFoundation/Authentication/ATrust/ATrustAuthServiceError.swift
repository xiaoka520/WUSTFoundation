import Foundation

public enum ATrustAuthServiceError: Error {
    case invalidURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case rejected(Int)
    case invalidConfiguration
    case casLoginNotFound
    case invalidRedirect
    case serviceNotFound
    case requestFailed(operation: String, statusCode: Int, businessCode: Int?)
    case invalidEnvironmentTicket
    case invalidDeviceID
    case casCallbackRejected
}
