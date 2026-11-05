public enum TimetableError: Error, Equatable {
    case invalidNumberList
    case invalidTimeFormat
    case missingCourseName
    case missingCourseTime
    case tableNotFound
    case invalidTableStructure
    case invalidURL
    case invalidFormEncoding
    case formNotFound
    case unsupportedForm
    case invalidResponse
    case unexpectedStatusCode(Int)
    case invalidEncoding
    case unexpectedRedirect
    case authenticationRequired
    case invalidTerm
    case selectionNotReflected
    case invalidDate
    case teachingWeekNotFound
    case invalidTeachingWeek
}
