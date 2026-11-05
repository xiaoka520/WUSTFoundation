import Testing
@testable import WUSTFoundation

private enum TimetableHTML {
    static let term = AcademicTerm(id: "sample-term", name: "示例学期")
    static let weekdays = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]

    static func course(
        name: String = "示例课程",
        time: String = "1-2,4(周)[01-02节]",
        location: String? = "示例教室"
    ) -> String {
        let place = location.map { "<font title='教室'>\($0)</font>" } ?? ""
        return "\(name)<br><font title='周次(节次)'>\(time)</font>\(place)"
    }

    static func page(cells: [String], weekdays: [String] = TimetableHTML.weekdays) -> String {
        let headers = weekdays.map { "<th>\($0)</th>" }.joined()
        let contents = cells.map {
            "<td><div class='kbcontent'>\($0)</div><div class='kbcontent sykb2'>隐藏的简化课表副本</div></td>"
        }.joined()
        return "<table id='kbtable'><tbody><tr><th></th>\(headers)</tr><tr><th>第一大节</th>\(contents)</tr><tr><th>备注</th><td colspan='7'>示例备注</td></tr></tbody></table>"
    }

    static func parse(_ cells: [String]) throws -> Timetable {
        try TimetableParser().parse(from: page(cells: cells), term: term, maxWeek: 30, maxSection: 12)
    }
}

@Suite
struct TimetableParserTests {
    @Test func emptyCellsPreserveSundayPositionAndExcludeSimplifiedCopies() throws {
        var cells = Array(repeating: "", count: 7)
        cells[6] = TimetableHTML.course(time: "1-15(周)[12节]")
        let timetable = try TimetableHTML.parse(cells)
        let meeting = try #require(timetable.meetings.first)
        #expect(timetable.meetings.count == 1)
        #expect(meeting.weekday == .sunday)
        #expect(meeting.sections == [12])
        #expect(meeting.weeks == Array(1...15))
    }

    @Test func sameCellCoursesKeepDifferentLocationsAndRemoveOnlyExactDuplicates() throws {
        let first = TimetableHTML.course(location: "示例教室 A")
        let second = TimetableHTML.course(location: "示例教室 B")
        let content = [first, first, second].joined(separator: "<br>---------------------<br>")
        let timetable = try TimetableHTML.parse([content, "", "", "", "", "", ""])
        #expect(timetable.meetings.count == 2)
        #expect(Set(timetable.meetings.compactMap(\.location)) == ["示例教室 A", "示例教室 B"])
        #expect(timetable.meetings.allSatisfy { $0.weeks == [1, 2, 4] && $0.sections == [1, 2] })
    }

    @Test func missingOptionalFieldsRemainNil() throws {
        let timetable = try TimetableHTML.parse([TimetableHTML.course(location: nil), "", "", "", "", "", ""])
        let meeting = try #require(timetable.meetings.first)
        #expect(meeting.teacher == nil)
        #expect(meeting.teachingClass == nil)
        #expect(meeting.location == nil)
        #expect(meeting.courseID == nil)
    }

    @Test func filtersPreserveGapsAndOriginalWeekList() throws {
        let timetable = try TimetableHTML.parse([TimetableHTML.course(), "", "", "", "", "", ""])
        #expect(timetable.meetings(inWeek: 3).isEmpty)
        #expect(timetable.meetings(inWeek: 2, on: .sunday).isEmpty)
        #expect(timetable.meetings(inWeek: 2, on: .monday).first?.weeks == [1, 2, 4])
    }

    @Test func validEmptyGridIsDifferentFromMissingTable() throws {
        #expect(try TimetableHTML.parse(Array(repeating: "&nbsp;<br>", count: 7)).meetings.isEmpty)
        #expect(throws: TimetableError.tableNotFound) {
            try TimetableParser().parse(from: "<html></html>", term: TimetableHTML.term, maxWeek: 30, maxSection: 12)
        }
    }

    @Test func wrongWeekdayOrderAndMissingCellAreRejected() {
        let cells = Array(repeating: "", count: 7)
        let weekdays = Array(TimetableHTML.weekdays.reversed())
        #expect(throws: TimetableError.invalidTableStructure) {
            try TimetableParser().parse(
                from: TimetableHTML.page(cells: cells, weekdays: weekdays),
                term: TimetableHTML.term, maxWeek: 30, maxSection: 12
            )
        }
        #expect(throws: TimetableError.invalidTableStructure) {
            try TimetableHTML.parse(Array(repeating: "", count: 6))
        }
    }

    @Test func nonemptyBrokenCourseIsNotSilentlyDiscarded() {
        #expect(throws: TimetableError.missingCourseTime) {
            try TimetableHTML.parse(["示例课程但没有时间", "", "", "", "", "", ""])
        }
        #expect(throws: TimetableError.missingCourseName) {
            try TimetableHTML.parse([TimetableHTML.course(name: ""), "", "", "", "", "", ""])
        }
        #expect(throws: TimetableError.invalidTimeFormat) {
            let course = TimetableHTML.course() + "<font title='周次(节次)'>5(周)[03节]</font>"
            return try TimetableHTML.parse([course, "", "", "", "", "", ""])
        }
    }

    @Test func termIDsAndDisplayNamesRemainSeparateFields() throws {
        let html = "<select id='xnxq01id'><option value='sample-next'>示例下学期</option><option value='sample-current' selected>示例本学期</option></select>"
        let result = try TimetableParser().parseAcademicTerms(from: html)
        #expect(result.terms.count == 2)
        #expect(result.selectedTermID == "sample-current")
        #expect(result.terms[1].name == "示例本学期")
    }

    @Test func termWithoutExplicitSelectionRemainsUnknown() throws {
        let result = try TimetableParser().parseAcademicTerms(
            from: "<select id='xnxq01id'><option value='sample'>示例学期</option></select>"
        )
        #expect(result.selectedTermID == nil)
    }

    @Test(arguments: ["", "1,,2", "3-1", "1-", "1-3-5", "0", "-1", "31", "1-31", "1.5"])
    func malformedNumberListsThrow(_ text: String) {
        #expect(throws: TimetableError.invalidNumberList) {
            try TimetableTimeParser().parseNumberList(from: text, upperBound: 30)
        }
    }

    @Test func disjointWeeksAndSectionsAreNotExpandedAcrossGaps() throws {
        let time = try TimetableTimeParser().parse(from: "1-2,4,4(周)[01,03-04节]", maxWeek: 30, maxSection: 12)
        #expect(time.weeks == [1, 2, 4])
        #expect(time.sections == [1, 3, 4])
    }

    @Test(arguments: ["1-2周[01-02节]", "1-2(周)[01-02节", "1-9(单周)[01-02节]"])
    func unsupportedTimeFormatsThrow(_ text: String) {
        #expect(throws: TimetableError.invalidTimeFormat) {
            try TimetableTimeParser().parse(from: text, maxWeek: 30, maxSection: 12)
        }
    }
}
