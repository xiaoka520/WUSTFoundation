import Foundation
import SwiftSoup

public enum StudentInfoParserError: Error, Equatable {
    case tableNotFound
    case fieldNotFound(String)
}

public struct StudentInfoParser {
    private func findTable(in html: String) throws -> Element {
        let document = try SwiftSoup.parse(html)

        guard let table = try document.getElementById("xjkpTable") else {
            throw StudentInfoParserError.tableNotFound
        }

        return table
    }

    private func parseLabeledField(
        in table: Element,
        row: Int,
        column: Int,
        label: String
    ) throws -> String {

        let text = try readCellText(
            in: table,
            row: row,
            column: column,
            fieldName: label
        )

        guard text.hasPrefix(label) else {
            throw StudentInfoParserError.fieldNotFound(label)
        }

        let value = String(text.dropFirst(label.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else {
            throw StudentInfoParserError.fieldNotFound(label)
        }

        return value
    }
    // MARK: 学号 院系 专业 班级
    func parseStudentID(from html: String) throws -> String {
        let table = try findTable(in: html)

        return try parseLabeledField(in: table, row: 3, column: 5, label: "学号：")
    }
    func parseCollege(from html: String) throws -> String {
        let table = try findTable(in: html)

        return try parseLabeledField(in: table, row: 3, column: 1, label: "院系：")
    }
    func parseMajor(from html: String) throws -> String {
        let table = try findTable(in: html)

        return try parseLabeledField(in: table, row: 3, column: 2, label: "专业：")
    }
    func parseClassName(from html: String) throws -> String {
        let table = try findTable(in: html)

        return try parseLabeledField(in: table, row: 3, column: 4, label: "班级：")
    }

    private func readCellText(
        in table: Element,
        row: Int,
        column: Int,
        fieldName: String
    ) throws -> String {
        let selector = "tbody > tr:nth-child(\(row)) > td:nth-child(\(column))"
        guard let cell = try table.select(selector).first() else {
            throw StudentInfoParserError.fieldNotFound(fieldName)
        }

        let text = try cell.text()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    // MARK: 姓名 性别 生日 籍贯 民族 身份证
    func parseName(from html: String) throws -> String {
        let table = try findTable(in: html)

        return try readCellText(in: table, row: 4, column: 2, fieldName: "姓名")
    }
    func parseSex(from html: String) throws -> String {
        let table = try findTable(in: html)

        return try readCellText(in: table, row: 4, column: 4, fieldName: "性别")
    }
    func parseBirthday(from html: String) throws -> String {
        let table = try findTable(in: html)

        return try readCellText(in: table, row: 5, column: 2, fieldName: "出生日期")
    }
    func parseHometown(from html: String) throws -> String {
        let table = try findTable(in: html)

        return try readCellText(in: table, row: 7, column: 2, fieldName: "籍贯")
    }
    func parseNationality(from html: String) throws -> String {
        let table = try findTable(in: html)

        return try readCellText(in: table, row: 8, column: 4, fieldName: "民族")
    }
    func parseIDNumber(from html: String) throws -> String {
        let table = try findTable(in: html)

        return try readCellText(
            in: table,
            row: 50,
            column: 4,
            fieldName: "身份证编号"
        )
    }

    public init() {}

    public func parse(from html: String) throws -> StudentInfo {
        let table = try findTable(in: html)

        let studentID = try parseLabeledField(
            in: table,
            row: 3,
            column: 5,
            label: "学号："
        )
        let college = try parseLabeledField(
            in: table,
            row: 3,
            column: 1,
            label: "院系："
        )
        let major = try parseLabeledField(
            in: table,
            row: 3,
            column: 2,
            label: "专业："
        )
        let className = try parseLabeledField(
            in: table,
            row: 3,
            column: 4,
            label: "班级："
        )
        let name = try readCellText(
            in: table,
            row: 4,
            column: 2,
            fieldName: "姓名"
        )
        let sex = try readCellText(
            in: table,
            row: 4,
            column: 4,
            fieldName: "性别"
        )
        let birthday = try readCellText(
            in: table,
            row: 5,
            column: 2,
            fieldName: "出生日期"
        )
        let hometown = try readCellText(
            in: table,
            row: 7,
            column: 2,
            fieldName: "籍贯"
        )
        let nationality = try readCellText(
            in: table,
            row: 8,
            column: 4,
            fieldName: "民族"
        )
        let idNumber = try readCellText(
            in: table,
            row: 50,
            column: 4,
            fieldName: "身份证编号"
        )

        return StudentInfo(
            name: name,
            studentID: studentID,
            college: college,
            major: major,
            className: className,
            birthday: birthday,
            sex: sex,
            nationality: nationality,
            hometown: hometown,
            idNumber: idNumber
        )
    }
}
