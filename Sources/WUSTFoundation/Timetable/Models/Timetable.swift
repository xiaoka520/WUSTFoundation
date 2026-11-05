public struct Timetable: Codable, Hashable, Sendable {
    public let term: AcademicTerm
    public let meetings: [CourseMeeting]

    public init(term: AcademicTerm, meetings: [CourseMeeting]) {
        self.term = term
        self.meetings = meetings
    }

    public func meetings(inWeek week: Int) -> [CourseMeeting] {
        return meetings.filter { meeting in
            meeting.weeks.contains(week)
        }
    }

    public func meetings(
        inWeek week: Int,
        on weekday: Weekday
    ) -> [CourseMeeting] {
        return meetings(inWeek: week).filter { meeting in
            meeting.weekday == weekday
        }
    }
}
