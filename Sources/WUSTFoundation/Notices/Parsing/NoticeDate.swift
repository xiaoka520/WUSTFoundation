import Foundation

struct NoticeDate: Comparable {
    let year: Int
    let month: Int
    let day: Int

    var value: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func < (lhs: NoticeDate, rhs: NoticeDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func parseExact(_ text: String) -> NoticeDate? {
        guard text.range(of: #"\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z"#, options: .regularExpression) != nil else { return nil }
        return extract(from: text)
    }

    static func extract(from text: String) -> NoticeDate? {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![0-9])([0-9]{4})\s*[-年/.]\s*([0-9]{1,2})\s*[-月/.]\s*([0-9]{1,2})(?:日)?(?![0-9])"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let yearRange = Range(match.range(at: 1), in: text),
              let monthRange = Range(match.range(at: 2), in: text),
              let dayRange = Range(match.range(at: 3), in: text),
              let year = Int(text[yearRange]), let month = Int(text[monthRange]), let day = Int(text[dayRange]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(era: 1, year: year, month: month, day: day, hour: 12)) else { return nil }
        let fields = calendar.dateComponents([.year, .month, .day], from: date)
        guard fields.year == year, fields.month == month, fields.day == day else { return nil }
        return NoticeDate(year: year, month: month, day: day)
    }

}
