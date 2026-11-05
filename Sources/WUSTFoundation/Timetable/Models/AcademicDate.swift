import Foundation

public struct AcademicDate: Codable, Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = Self.arithmeticCalendar.date(from: DateComponents(
                era: 1, year: year, month: month, day: day, hour: 12
              )) else {
            throw TimetableError.invalidDate
        }
        let components = Self.arithmeticCalendar.dateComponents([.year, .month, .day], from: date)
        guard components.year == year, components.month == month, components.day == day else {
            throw TimetableError.invalidDate
        }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(yyyyMMdd value: String) throws {
        guard value.utf8.count == 8, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(4).prefix(2)),
              let day = Int(value.suffix(2)) else {
            throw TimetableError.invalidDate
        }
        try self.init(year: year, month: month, day: day)
    }

    public init(date: Date) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let timeZone = TimeZone(identifier: "Asia/Shanghai") else {
            throw TimetableError.invalidDate
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard components.era == 1,
              let year = components.year, let month = components.month, let day = components.day else {
            throw TimetableError.invalidDate
        }
        try self.init(year: year, month: month, day: day)
    }

    public var yyyyMMdd: String {
        String(format: "%04d%02d%02d", year, month, day)
    }

    public static func today() throws -> AcademicDate {
        try AcademicDate(date: Date())
    }

    public func adding(days: Int) throws -> AcademicDate {
        guard days >= -(9999 * 366), days <= 9999 * 366,
              let date = Self.arithmeticCalendar.date(byAdding: .day, value: days, to: try foundationDate()) else {
            throw TimetableError.invalidDate
        }
        let components = Self.arithmeticCalendar.dateComponents([.era, .year, .month, .day], from: date)
        guard components.era == 1,
              let year = components.year, let month = components.month, let day = components.day else {
            throw TimetableError.invalidDate
        }
        return try AcademicDate(year: year, month: month, day: day)
    }

    public func weekday() throws -> Weekday {
        let value = Self.arithmeticCalendar.component(.weekday, from: try foundationDate())
        guard let weekday = Weekday(rawValue: value == 1 ? 7 : value - 1) else {
            throw TimetableError.invalidDate
        }
        return weekday
    }

    public static func < (lhs: AcademicDate, rhs: AcademicDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(yyyyMMdd: value)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a valid yyyyMMdd date.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(yyyyMMdd)
    }

    var requestValue: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    func days(since other: AcademicDate) throws -> Int {
        guard let days = Self.arithmeticCalendar.dateComponents(
            [.day], from: try other.foundationDate(), to: try foundationDate()
        ).day else {
            throw TimetableError.invalidDate
        }
        return days
    }

    private func foundationDate() throws -> Date {
        guard let date = Self.arithmeticCalendar.date(from: DateComponents(
            era: 1, year: year, month: month, day: day, hour: 12
        )) else {
            throw TimetableError.invalidDate
        }
        return date
    }

    private static var arithmeticCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
