import Foundation

struct ExamTimeParser {
    func parse(_ text: String) -> ExamTimeRange? {
        let pattern = #"^\s*(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})\s*[~～]\s*(\d{2}):(\d{2})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let values = (1...7).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[range])
        }
        guard values.count == 7, (1...9999).contains(values[0]),
              (1...12).contains(values[1]), (1...31).contains(values[2]),
              (0...23).contains(values[3]), (0...59).contains(values[4]),
              (0...23).contains(values[5]), (0...59).contains(values[6]),
              let zone = TimeZone(identifier: "Asia/Shanghai") else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func makeDate(hour: Int, minute: Int) -> Date? {
            let components = DateComponents(
                era: 1, year: values[0], month: values[1], day: values[2], hour: hour, minute: minute, second: 0
            )
            guard let date = calendar.date(from: components) else { return nil }
            let actual = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)
            guard actual.era == 1, actual.year == values[0], actual.month == values[1], actual.day == values[2],
                  actual.hour == hour, actual.minute == minute, actual.second == 0 else { return nil }
            return date
        }
        guard let start = makeDate(hour: values[3], minute: values[4]),
              let end = makeDate(hour: values[5], minute: values[6]), end > start else { return nil }
        return ExamTimeRange(start: start, end: end)
    }
}
