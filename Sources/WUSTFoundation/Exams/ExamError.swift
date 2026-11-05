public enum ExamError: Error, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case unexpectedRedirect
    case authenticationRequired
    case invalidEncoding
    case formNotFound
    case unsupportedForm
    case invalidQuery
    case invalidFormEncoding
    case tableNotFound
    case invalidTableStructure
    case unsupportedPagination
    case selectionNotReflected
}
