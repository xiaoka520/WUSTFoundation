import Testing
@testable import WUSTFoundation

private func studentIDHTML(_ cell: String) -> String {
    "<table id='xjkpTable'><tbody><tr><td></td></tr><tr><td></td></tr><tr><td></td><td></td><td></td><td></td>\(cell)</tr></tbody></table>"
}

@Test(arguments: ["学号：001234", " 学号： 001234 ", "学号：<span>001234</span>"])
func studentIDExtraction(_ text: String) throws {
    #expect(try StudentInfoParser().parseStudentID(from: studentIDHTML("<td>\(text)</td>")) == "001234")
}

@Test(arguments: ["<td>学号：</td>", "<td>姓名：示例</td>", ""])
func missingStudentID(_ cell: String) {
    #expect(throws: StudentInfoParserError.fieldNotFound("学号：")) {
        try StudentInfoParser().parseStudentID(from: studentIDHTML(cell))
    }
}

@Test func missingTable() {
    #expect(throws: StudentInfoParserError.tableNotFound) {
        try StudentInfoParser().parseStudentID(from: "<html></html>")
    }
}
