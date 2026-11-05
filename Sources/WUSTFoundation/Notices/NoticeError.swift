public enum NoticeError: Error, Equatable {
    case invalidURL
    case unsupportedURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case unexpectedRedirect
    case authenticationRequired
    case invalidEncoding
    case listNotFound
    case titleNotFound
    case bodyNotFound
    case missingPublicationDate
    case filteredPublicationDate
    case invalidDatePolicy
    case invalidConfiguration
    case invalidDocument
    case documentTooLarge
}
