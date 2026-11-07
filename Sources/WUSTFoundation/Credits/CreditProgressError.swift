public enum CreditProgressError: Error, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case unexpectedRedirect
    case authenticationRequired
    case invalidEncoding
    case tableNotFound(String)
    case invalidTableStructure(String)
    case invalidNumber(String)
}
