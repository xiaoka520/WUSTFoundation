import Foundation

extension WUSTLoginClient {
    public func fetchAcademicTerms() async throws -> AcademicTermList {
        try await withUndergraduateSession(retryOnAuthenticationFailure: Self.isTimetableAuthenticationFailure) { cookie, session in
            try await TimetableService().fetchAcademicTerms(cookie: cookie, using: session)
        }
    }

    public func fetchTimetable(
        term: AcademicTerm,
        maxWeek: Int = 30,
        maxSection: Int = 12
    ) async throws -> Timetable {
        guard maxWeek > 0, maxSection > 0 else {
            throw TimetableError.invalidNumberList
        }
        return try await withUndergraduateSession(retryOnAuthenticationFailure: Self.isTimetableAuthenticationFailure) { cookie, session in
            try await TimetableService(maxWeek: maxWeek, maxSection: maxSection).fetchTimetable(
                term: term,
                cookie: cookie,
                using: session
            )
        }
    }

    public func fetchTeachingCalendar(on date: AcademicDate? = nil) async throws -> TeachingCalendar {
        let referenceDate: AcademicDate
        if let date {
            referenceDate = date
        } else {
            referenceDate = try AcademicDate.today()
        }
        return try await withUndergraduateSession(retryOnAuthenticationFailure: Self.isTimetableAuthenticationFailure) { cookie, session in
            try await TeachingCalendarService().fetchTeachingCalendar(
                on: referenceDate,
                cookie: cookie,
                using: session
            )
        }
    }

    private nonisolated static func isTimetableAuthenticationFailure(_ error: any Error) -> Bool {
        guard let error = error as? TimetableError else { return false }
        return error == .authenticationRequired
    }
}
