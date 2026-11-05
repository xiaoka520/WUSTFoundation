public enum TrainingPlanError: Error, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case unexpectedRedirect
    case authenticationRequired
    case invalidEncoding
    case planNotFound
    case titleNotFound
    case invalidTableStructure
    case contentTooLarge
}
