import Foundation

public struct NoticeDatePolicy: Sendable {
    public let excludedDates: Set<String>
    public let earliestDate: String?
    public let latestDate: String?

    public init(
        excludedDates: Set<String> = ["1980-01-01"],
        earliestDate: String? = nil,
        latestDate: String? = nil
    ) {
        self.excludedDates = excludedDates
        self.earliestDate = earliestDate
        self.latestDate = latestDate
    }

    func resolve() throws -> NoticeDateRange {
        guard excludedDates.allSatisfy({ NoticeDate.parseExact($0) != nil }) else {
            throw NoticeError.invalidDatePolicy
        }
        let earliest: NoticeDate?
        if let earliestDate {
            guard let value = NoticeDate.parseExact(earliestDate) else { throw NoticeError.invalidDatePolicy }
            earliest = value
        } else {
            earliest = nil
        }
        let latest: NoticeDate?
        if let latestDate {
            guard let value = NoticeDate.parseExact(latestDate) else { throw NoticeError.invalidDatePolicy }
            latest = value
        } else {
            latest = nil
        }
        if let earliest, let latest, earliest > latest { throw NoticeError.invalidDatePolicy }
        return NoticeDateRange(earliest: earliest, latest: latest, excludedDates: excludedDates)
    }
}

struct NoticeDateRange {
    let earliest: NoticeDate?
    let latest: NoticeDate?
    let excludedDates: Set<String>

    func allows(_ date: NoticeDate) -> Bool {
        !excludedDates.contains(date.value) && (latest.map { date <= $0 } ?? true) && (earliest.map { date >= $0 } ?? true)
    }
}
