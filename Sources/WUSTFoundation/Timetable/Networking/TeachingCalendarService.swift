import Foundation

public struct TeachingCalendarService: Sendable {
    public init() {}

    public func fetchTeachingCalendar(
        on date: AcademicDate,
        cookie: String,
        using session: URLSession
    ) async throws -> TeachingCalendar {
        guard !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TimetableError.authenticationRequired
        }
        let request = try TimetableRequestFactory().makeTeachingCalendarRequest(date: date, cookie: cookie)
        let page = try await TimetablePageLoader().fetch(request, using: session)
        return try TeachingCalendarParser().parse(from: page.html, referenceDate: date)
    }
}
