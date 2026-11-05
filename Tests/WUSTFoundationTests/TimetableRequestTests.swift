import Foundation
import Testing
@testable import WUSTFoundation

@Suite
struct TimetableRequestTests {
    private let html = """
    <form id="Form1" method="POST" action="">
      <input type="hidden" name="repeated" value="first">
      <input type="hidden" name="repeated" value="second">
      <input type="hidden" name="special" value="A+B &amp; 示例">
      <input type="checkbox" name="checked" checked>
      <input type="checkbox" name="unchecked" value="unused">
      <input type="hidden" name="disabled" value="unused" disabled>
      <input type="submit" name="submit" value="unused">
      <select name="xnxq01id"><option value="sample-old" selected>示例学期</option></select>
      <select name="zc"><option value="">全部</option><option value="4" selected>第四周</option></select>
      <select name="kbjcmsid"><option value="sample-template" selected>示例模板</option></select>
      <select name="first-option"><option value="first">第一项</option><option value="second">第二项</option></select>
      <textarea name="note">示例备注</textarea>
    </form>
    """

    private func sourceURL() throws -> URL {
        try #require(URL(string: "https://bkjx.wust.edu.cn/jsxsd/xskb/xskb_list.do"))
    }

    private func fields(in request: URLRequest) throws -> [URLQueryItem] {
        let body = try #require(request.httpBody)
        var components = URLComponents()
        components.percentEncodedQuery = String(decoding: body, as: UTF8.self)
        return try #require(components.queryItems)
    }

    @Test func formRetainsRepeatedFieldsAndSubmitsOnlySuccessfulControls() throws {
        let form = try TimetableFormParser().parse(from: html, sourceURL: sourceURL())
        #expect(form.fields.filter { $0.name == "repeated" }.map(\.value) == ["first", "second"])
        #expect(form.fields.first { $0.name == "checked" }?.value == "on")
        #expect(form.fields.first { $0.name == "first-option" }?.value == "first")
        #expect(form.fields.first { $0.name == "note" }?.value == "示例备注")
        #expect(!form.fields.contains { ["unchecked", "disabled", "submit"].contains($0.name) })
        #expect(form.actionURL == (try sourceURL()))
    }

    @Test func semesterPostReplacesOnlyTermAndWeekAndPreservesLiteralPlus() throws {
        let form = try TimetableFormParser().parse(from: html, sourceURL: sourceURL())
        let request = try TimetableRequestFactory().makeTimetableRequest(
            url: form.actionURL, fields: form.fields, termID: "sample-new", cookie: "session=synthetic"
        )
        let items = try fields(in: request)
        #expect(items.filter { $0.name == "xnxq01id" }.map(\.value) == ["sample-new"])
        #expect(items.filter { $0.name == "zc" }.map(\.value) == [""])
        #expect(items.filter { $0.name == "repeated" }.count == 2)
        #expect(items.first { $0.name == "kbjcmsid" }?.value == "sample-template")
        #expect(items.first { $0.name == "special" }?.value == "A+B & 示例")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "session=synthetic")
    }

    @Test func calendarPostUsesISODateInsteadOfAnInferredSemester() throws {
        let request = try TimetableRequestFactory().makeTeachingCalendarRequest(
            date: AcademicDate(yyyyMMdd: "20261105"), cookie: "session=synthetic"
        )
        #expect(request.url?.path == "/jsxsd/framework/main_index_loadkb.jsp")
        #expect(request.httpMethod == "POST")
        #expect(try fields(in: request) == [URLQueryItem(name: "rq", value: "2026-11-05")])
    }

    @Test func foreignActionAndWrongMethodAreRejectedBeforeCreatingRequests() throws {
        let url = try sourceURL()
        #expect(throws: TimetableError.unsupportedForm) {
            try TimetableFormParser().parse(
                from: html.replacingOccurrences(of: "action=\"\"", with: "action=\"https://example.invalid/collect\""),
                sourceURL: url
            )
        }
        #expect(throws: TimetableError.unsupportedForm) {
            try TimetableFormParser().parse(from: html.replacingOccurrences(of: "method=\"POST\"", with: "method=\"GET\""), sourceURL: url)
        }
    }
}
