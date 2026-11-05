import Foundation
import Testing
@testable import WUSTFoundation

@Suite
struct TeachingCalendarTests {
    private func makeCalendar() throws -> TeachingCalendar {
        try TeachingCalendar(referenceDate: AcademicDate(yyyyMMdd: "20261105"), referenceWeek: 10, totalWeeks: 22)
    }

    @Test(arguments: [
        ##"<script>$("#li_showWeek").html("<span>第10周</span>/22周");</script>"##,
        ##"<script>jQuery('#li_showWeek').html('<span>第 10 周</span> / 22 周');</script>"##,
        ##"<script>$("#li_showWeek").html("<span class=\"current\">第10周<\/span>/22周");</script>"##
    ])
    func parsesOnlyTheWeekLabelWithoutExecutingScripts(_ html: String) throws {
        let result = try TeachingCalendarParser().parse(from: html, referenceDate: AcademicDate(yyyyMMdd: "20261105"))
        #expect(result.referenceWeek == 10)
        #expect(result.totalWeeks == 22)
        #expect(result.firstMonday.yyyyMMdd == "20260831")
        #expect(result.lastSunday.yyyyMMdd == "20270131")
    }

    @Test func totalWeeksComeFromResponseInsteadOfAConstant() throws {
        let result = try TeachingCalendarParser().parse(
            from: "<li id='li_showWeek'><span>第2周</span>/18周</li>",
            referenceDate: AcademicDate(yyyyMMdd: "20260223")
        )
        #expect(result.totalWeeks == 18)
    }

    @Test func unrelatedTextCannotBecomeAWeekAnchor() throws {
        let date = try AcademicDate(yyyyMMdd: "20261105")
        #expect(throws: TimetableError.teachingWeekNotFound) {
            try TeachingCalendarParser().parse(from: "<p>第10周/22周</p><script>var message='第10周/22周';</script>", referenceDate: date)
        }
        #expect(throws: TimetableError.teachingWeekNotFound) {
            try TeachingCalendarParser().parse(from: "<div>没有周次标签的示例片段</div>", referenceDate: date)
        }
    }

    @Test func conflictingWeekLabelsAreRejected() throws {
        let html = ##"<li id='li_showWeek'>第9周/22周</li><script>$("#li_showWeek").html('<span>第10周</span>/22周');</script>"##
        let date = try AcademicDate(yyyyMMdd: "20261105")
        #expect(throws: TimetableError.invalidTeachingWeek) {
            try TeachingCalendarParser().parse(from: html, referenceDate: date)
        }
    }

    @Test func sundayAndMondayFallInDifferentWeeks() throws {
        let calendar = try makeCalendar()
        #expect(try calendar.week(containing: AcademicDate(yyyyMMdd: "20261108")) == 10)
        #expect(try calendar.week(containing: AcademicDate(yyyyMMdd: "20261109")) == 11)
        #expect(try calendar.date(inWeek: 10, on: .thursday).yyyyMMdd == "20261105")
    }

    @Test func rangesCrossYearAndIncludeBothTermEndpoints() throws {
        let calendar = try makeCalendar()
        let first = try calendar.range(ofWeek: 1)
        let last = try calendar.range(ofWeek: 22)
        let newYear = try calendar.range(ofWeek: 18)
        #expect(first.startDate.yyyyMMdd == "20260831")
        #expect(first.endDate.yyyyMMdd == "20260906")
        #expect(last.startDate.yyyyMMdd == "20270125")
        #expect(last.endDate.yyyyMMdd == "20270131")
        #expect(newYear.startDate.yyyyMMdd == "20261228")
        #expect(newYear.endDate.yyyyMMdd == "20270103")
        #expect(try calendar.week(containing: first.startDate) == 1)
        #expect(try calendar.week(containing: last.endDate) == 22)
        #expect(try calendar.week(containing: AcademicDate(yyyyMMdd: "20260830")) == nil)
        #expect(try calendar.week(containing: AcademicDate(yyyyMMdd: "20270201")) == nil)
    }

    @Test(arguments: [-1, 0, 23])
    func invalidWeekRequestsThrow(_ week: Int) throws {
        let calendar = try makeCalendar()
        #expect(throws: TimetableError.invalidTeachingWeek) { try calendar.range(ofWeek: week) }
    }

    @Test(arguments: ["20260230", "20230229", "20261301", "2026115", "2026-11-05", "00000101"])
    func invalidDatesCannotBeNormalizedIntoAnotherDay(_ value: String) {
        #expect(throws: TimetableError.invalidDate) { try AcademicDate(yyyyMMdd: value) }
    }

    @Test func leapDayAndShanghaiDayBoundaryAreHandled() throws {
        #expect(try AcademicDate(yyyyMMdd: "20240229").adding(days: 1).yyyyMMdd == "20240301")
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-11-05T16:30:00Z"))
        #expect(try AcademicDate(date: instant).yyyyMMdd == "20261106")
    }

    @Test func cachedCalendarRoundTripsAndValidatesDateStrings() throws {
        let original = try makeCalendar()
        let encoded = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(TeachingCalendar.self, from: encoded) == original)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["referenceDate"] as? String == "20261105")
        #expect(object["firstMonday"] as? String == "20260831")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AcademicDate.self, from: Data(#""20260230""#.utf8))
        }
    }
}
