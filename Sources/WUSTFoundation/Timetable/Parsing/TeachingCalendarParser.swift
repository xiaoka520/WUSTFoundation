import Foundation
import SwiftSoup

public struct TeachingCalendarParser {
    public init() {}

    public func parse(from html: String, referenceDate: AcademicDate) throws -> TeachingCalendar {
        let document = try SwiftSoup.parse(html)
        var labels: [String] = []
        if let element = try document.getElementById("li_showWeek") {
            labels.append(try element.html())
        }

        let assignmentPattern = #"(?:\$|jQuery)\(\s*["']#li_showWeek["']\s*\)\s*\.html\(\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)')\s*\)"#
        let assignmentRegex = try NSRegularExpression(pattern: assignmentPattern)
        for script in try document.select("script") {
            let source = script.data()
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in assignmentRegex.matches(in: source, range: range) {
                let capture = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                guard let range = Range(capture, in: source) else {
                    throw TimetableError.invalidResponse
                }
                let label = String(source[range])
                    .replacingOccurrences(of: #"\/"#, with: "/")
                    .replacingOccurrences(of: #"\""#, with: "\"")
                    .replacingOccurrences(of: #"\'"#, with: "'")
                labels.append(label)
            }
        }

        let weekRegex = try NSRegularExpression(pattern: #"第\s*([0-9]+)\s*周\s*/\s*([0-9]+)\s*周"#)
        var counts: (week: Int, total: Int)?
        for label in labels {
            let fragment = try SwiftSoup.parseBodyFragment(label)
            let text = try fragment.text()
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in weekRegex.matches(in: text, range: range) {
                guard let weekRange = Range(match.range(at: 1), in: text),
                      let totalRange = Range(match.range(at: 2), in: text),
                      let week = Int(text[weekRange]),
                      let total = Int(text[totalRange]),
                      week >= 1, total >= week else {
                    throw TimetableError.invalidTeachingWeek
                }
                if let counts, counts.week != week || counts.total != total {
                    throw TimetableError.invalidTeachingWeek
                }
                counts = (week: week, total: total)
            }
        }
        guard let counts else { throw TimetableError.teachingWeekNotFound }
        return try TeachingCalendar(
            referenceDate: referenceDate,
            referenceWeek: counts.week,
            totalWeeks: counts.total
        )
    }
}
