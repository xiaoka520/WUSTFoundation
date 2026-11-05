import Foundation
import SwiftSoup

public struct TimetableParser {
    public init() {}

    private func readOptionalField(
        in element: Element,
        title: String
    ) throws -> String? {
        let fields = try element.select("font[title=\"\(title)\"]")
        guard !fields.isEmpty else {
            return nil
        }
        let text = try fields.text().trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if text.isEmpty {
            return nil
        } else {
            return text
        }
    }

    private func parseCourseBlock(
        from element: Element,
        weekday: Weekday,
        maxWeek: Int,
        maxSection: Int
    ) throws -> CourseMeeting {
        let name = element.ownText()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw TimetableError.missingCourseName
        }

        let timeElements = try element.select("font[title=\"周次(节次)\"]")
        guard !timeElements.isEmpty else {
            throw TimetableError.missingCourseTime
        }
        guard timeElements.count == 1 else {
            throw TimetableError.invalidTimeFormat
        }
        guard let timeElement = timeElements.first() else {
            throw TimetableError.invalidTimeFormat
        }

        let timeText = try timeElement.text()
        let time = try TimetableTimeParser().parse(
            from: timeText,
            maxWeek: maxWeek,
            maxSection: maxSection
        )
        let teacher = try readOptionalField(in: element, title: "老师")
        let teachingClass = try readOptionalField(in: element, title: "课堂名称")
        let location = try readOptionalField(in: element, title: "教室")
        return CourseMeeting(
            name: name,
            weekday: weekday,
            weeks: time.weeks,
            sections: time.sections,
            teacher: teacher,
            teachingClass: teachingClass,
            location: location
        )
    }

    public func parse(
        from html: String,
        term: AcademicTerm,
        maxWeek: Int,
        maxSection: Int
    ) throws -> Timetable {
        guard maxWeek > 0 && maxSection > 0 else {
            throw TimetableError.invalidNumberList
        }

        let document = try SwiftSoup.parse(html)
        guard let table = try document.getElementById("kbtable") else {
            throw TimetableError.tableNotFound
        }
        let rows = try table.select("tr").array()
        guard let headerRow = rows.first else {
            throw TimetableError.invalidTableStructure
        }
        let headerCells = try headerRow.select("th").array()
        let weekdays = try headerCells.dropFirst().map { cell in
            try cell.text()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard weekdays == [
            "星期一", "星期二", "星期三", "星期四",
            "星期五", "星期六", "星期日"
        ] else {
            throw TimetableError.invalidTableStructure
        }
        var meetings: [CourseMeeting] = []
        var seen = Set<CourseMeeting>()
        var courseRowCount = 0

        for row in rows.dropFirst() {
            let cells = try row.select(".kbcontent:not(.sykb2)").array()
            if cells.isEmpty {
                continue
            }
            if cells.count != 7 {
                throw TimetableError.invalidTableStructure
            }
            courseRowCount += 1
            for (index, cell) in cells.enumerated() {
                guard let weekday = Weekday(rawValue: index + 1) else {
                    throw TimetableError.invalidTableStructure
                }
                let fragments = try cell.html()
                    .components(separatedBy: "---------------------")

                for fragment in fragments {
                    let fragmentDocument = try SwiftSoup.parseBodyFragment(fragment)
                    guard let block = fragmentDocument.body() else {
                        throw TimetableError.invalidTableStructure
                    }

                    let blockText = try block.text()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if blockText.isEmpty {
                        continue
                    }

                    let meeting = try parseCourseBlock(
                        from: block,
                        weekday: weekday,
                        maxWeek: maxWeek,
                        maxSection: maxSection
                    )
                    if seen.insert(meeting).inserted {
                        meetings.append(meeting)
                    }
                }
            }
        }

        guard courseRowCount > 0 else {
            throw TimetableError.invalidTableStructure
        }

        let sortedMeetings = meetings.sorted { left, right in
            if left.weekday != right.weekday {
                return left.weekday.rawValue < right.weekday.rawValue
            }

            let leftStart = left.sections.first ?? 0
            let rightStart = right.sections.first ?? 0
            if leftStart != rightStart {
                return leftStart < rightStart
            }

            if left.name != right.name {
                return left.name < right.name
            }
            if left.sections != right.sections {
                return left.sections.lexicographicallyPrecedes(right.sections)
            }
            if left.weeks != right.weeks {
                return left.weeks.lexicographicallyPrecedes(right.weeks)
            }
            let leftFields = [
                left.teacher ?? "", left.teachingClass ?? "",
                left.location ?? "", left.courseID ?? ""
            ]
            let rightFields = [
                right.teacher ?? "", right.teachingClass ?? "",
                right.location ?? "", right.courseID ?? ""
            ]
            return leftFields.lexicographicallyPrecedes(rightFields)
        }

        return Timetable(term: term, meetings: sortedMeetings)
    }

    public func parseAcademicTerms(
        from html: String
    ) throws -> AcademicTermList {
        let document = try SwiftSoup.parse(html)

        guard let select = try document.getElementById("xnxq01id") else {
            throw TimetableError.invalidTableStructure
        }

        let options = try select.select("option").array()
        var terms: [AcademicTerm] = []
        var selectedTermID: String? = nil
        for option in options {
            let id = try option.attr("value")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = try option.text()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !id.isEmpty && !name.isEmpty else {
                throw TimetableError.invalidTableStructure
            }

            let term = AcademicTerm(id: id, name: name)
            terms.append(term)

            if option.hasAttr("selected") {
                guard selectedTermID == nil else {
                    throw TimetableError.invalidTableStructure
                }
                selectedTermID = id
            }
        }
        guard !terms.isEmpty else {
            throw TimetableError.invalidTableStructure
        }

        return AcademicTermList(
            terms: terms,
            selectedTermID: selectedTermID
        )
    }
}
