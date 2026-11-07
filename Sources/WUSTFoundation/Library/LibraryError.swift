import Foundation

public enum LibraryError: Error, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case unexpectedRedirect
    case authenticationRequired
    case invalidEncoding
    case invalidPayload
    case invalidPagination
    case invalidBooklistID
    case serviceRejected(Int)
}
