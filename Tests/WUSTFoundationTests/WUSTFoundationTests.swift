import Testing
import Foundation
@testable import WUSTFoundation

//@Test func example() async throws {
//    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
//    // Swift Testing Documentation
//    // https://developer.apple.com/documentation/testing
//}

@Test func parseStudentIDFromHTML() async throws {
    
    let fileURL = URL(fileURLWithPath: "/Users/caoenming/Developer/WUSTFoundation/webPageData/学籍卡片.html")
    
    let html = try String(contentsOf: fileURL, encoding: .utf8)
    let parser = StudentInfoParser()
    let studentID = try parser.parseStudentID(from: html)
    
    #expect(studentID == "202613407173")
}
@Test func parseStudentIDThrowsWhenTableIsMissing() {
    let html = "<html><body>没有学籍表格</body></html>"
    let parser = StudentInfoParser()

    #expect(throws: StudentInfoParserError.tableNotFound) {
        try parser.parseStudentID(from: html)
    }
}

private func readSample(_ fileName: String) throws -> String {
    let directoryURL = URL(
        fileURLWithPath:
            "/Users/caoenming/Developer/WUSTFoundation/WUSTFoundation/TestData/synthetic"
    )

    let fileURL = directoryURL.appendingPathComponent(fileName)
    return try String(contentsOf: fileURL, encoding: .utf8)
}

@Test(arguments: [
    "student-id-normal.html",
    "student-id-whitespace.html"
])
func parseStudentIDFromValidSamples(fileName: String) throws {
    let html = try readSample(fileName)
    let parser = StudentInfoParser()

    let studentID = try parser.parseStudentID(from: html)

    #expect(studentID == "209900000001")
}

@Test(arguments: [
    "student-id-empty.html",
    "student-id-cell-missing.html",
    "student-id-label-mismatch.html"
])
func parseStudentIDThrowsForInvalidSamples(
    fileName: String
) throws {
    let html = try readSample(fileName)
    let parser = StudentInfoParser()

    #expect(throws: StudentInfoParserError.studentIDNotFound) {
        try parser.parseStudentID(from: html)
    }
}
