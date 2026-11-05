import Foundation

public struct TeachingWeek: Codable, Hashable, Sendable {
    public let number: Int
    public let startDate: AcademicDate
    public let endDate: AcademicDate
}

public struct TeachingCalendar: Codable, Hashable, Sendable {
    public let referenceDate: AcademicDate
    public let referenceWeek: Int
    public let totalWeeks: Int
    public let firstMonday: AcademicDate
    public let lastSunday: AcademicDate

    public init(referenceDate: AcademicDate, referenceWeek: Int, totalWeeks: Int) throws {
        guard referenceWeek >= 1, totalWeeks >= referenceWeek else {
            throw TimetableError.invalidTeachingWeek
        }
        let (offset, offsetOverflow) = (referenceWeek - 1).multipliedReportingOverflow(by: 7)
        let (length, lengthOverflow) = totalWeeks.multipliedReportingOverflow(by: 7)
        guard !offsetOverflow, !lengthOverflow else {
            throw TimetableError.invalidTeachingWeek
        }
        let weekday = try referenceDate.weekday()
        let referenceMonday = try referenceDate.adding(days: -(weekday.rawValue - 1))
        let firstMonday = try referenceMonday.adding(days: -offset)
        let lastSunday = try firstMonday.adding(days: length - 1)
        self.referenceDate = referenceDate
        self.referenceWeek = referenceWeek
        self.totalWeeks = totalWeeks
        self.firstMonday = firstMonday
        self.lastSunday = lastSunday
    }

    public func range(ofWeek week: Int) throws -> TeachingWeek {
        guard week >= 1, week <= totalWeeks else {
            throw TimetableError.invalidTeachingWeek
        }
        let (offset, overflow) = (week - 1).multipliedReportingOverflow(by: 7)
        guard !overflow else { throw TimetableError.invalidTeachingWeek }
        let startDate = try firstMonday.adding(days: offset)
        return TeachingWeek(number: week, startDate: startDate, endDate: try startDate.adding(days: 6))
    }

    public func week(containing date: AcademicDate) throws -> Int? {
        guard date >= firstMonday, date <= lastSunday else { return nil }
        return try date.days(since: firstMonday) / 7 + 1
    }

    public func date(inWeek week: Int, on weekday: Weekday) throws -> AcademicDate {
        try range(ofWeek: week).startDate.adding(days: weekday.rawValue - 1)
    }

    private enum CodingKeys: String, CodingKey {
        case referenceDate, referenceWeek, totalWeeks, firstMonday, lastSunday
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            referenceDate: container.decode(AcademicDate.self, forKey: .referenceDate),
            referenceWeek: container.decode(Int.self, forKey: .referenceWeek),
            totalWeeks: container.decode(Int.self, forKey: .totalWeeks)
        )
    }
}
