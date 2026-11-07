import Foundation
import SwiftSoup

public struct CreditProgressParser: Sendable {
    public init() {}

    public func parse(from html: String) throws -> CreditProgress {
        let document = try SwiftSoup.parse(html)
        let categoryRows = try rows(in: document, tableID: "byxf1", requiredColumns: [
            "课程性质", "课程属性", "要求学分", "已获得学分"
        ])
        let electiveRows = try rows(in: document, tableID: "byxf2", requiredColumns: [
            "类别", "要求学分", "已获得学分"
        ])
        let statisticsRows = try rows(in: document, tableID: "byxf3", requiredColumns: [
            "学期数", "已修门数", "已修学分", "学期平均学分", "不及格门数", "不及格学分",
            "未选门数", "未选学分", "必修未获学分门数", "必修未获学分"
        ])
        let courseRows = try rows(in: document, tableID: "pyfakcxdmx", requiredColumns: [
            "学期", "课程编码", "课程名称", "课程学分", "课程性质", "课程属性", "状态"
        ])
        guard statisticsRows.count <= 1 else { throw CreditProgressError.invalidTableStructure("byxf3") }

        let courseCategories = try categoryRows.map { try category(from: $0, nameColumn: "课程性质", tableID: "byxf1") }
        let generalElectives = try electiveRows.map { try category(from: $0, nameColumn: "类别", tableID: "byxf2") }
        let statistics = try statisticsRows.first.map { row in
            try CreditSemesterStatistics(
                semesterCount: integer(in: row, column: "学期数"),
                completedCourseCount: integer(in: row, column: "已修门数"),
                completedCredits: decimal(in: row, column: "已修学分"),
                averageCreditsPerSemester: decimal(in: row, column: "学期平均学分"),
                failedCourseCount: integer(in: row, column: "不及格门数"),
                failedCredits: decimal(in: row, column: "不及格学分"),
                unselectedCourseCount: integer(in: row, column: "未选门数"),
                unselectedCredits: decimal(in: row, column: "未选学分"),
                requiredCourseCountWithoutCredits: integer(in: row, column: "必修未获学分门数"),
                requiredCreditsNotEarned: decimal(in: row, column: "必修未获学分")
            )
        }
        let courses = try courseRows.map { row in
            guard let courseID = value(in: row, column: "课程编码"),
                  let courseName = value(in: row, column: "课程名称") else {
                throw CreditProgressError.invalidTableStructure("pyfakcxdmx")
            }
            return try CreditCourseProgress(
                termID: value(in: row, column: "学期"),
                courseID: courseID,
                courseName: courseName,
                credits: decimal(in: row, column: "课程学分"),
                courseNature: value(in: row, column: "课程性质"),
                courseAttribute: value(in: row, column: "课程属性"),
                status: value(in: row, column: "状态")
            )
        }
        return CreditProgress(
            courseCategories: courseCategories,
            generalElectives: generalElectives,
            pastSemesterStatistics: statistics,
            courses: courses
        )
    }

    private func category(from row: [String: String], nameColumn: String, tableID: String) throws -> CreditCategoryProgress {
        guard let name = value(in: row, column: nameColumn) else {
            throw CreditProgressError.invalidTableStructure(tableID)
        }
        return try CreditCategoryProgress(
            name: name,
            courseAttribute: value(in: row, column: "课程属性"),
            requiredCredits: decimal(in: row, column: "要求学分"),
            earnedCredits: decimal(in: row, column: "已获得学分")
        )
    }

    private func rows(in document: Document, tableID: String, requiredColumns: [String]) throws -> [[String: String]] {
        let tables = try document.select("table[id=\(tableID)]").array()
        guard let table = tables.first else { throw CreditProgressError.tableNotFound(tableID) }
        guard tables.count == 1 else { throw CreditProgressError.invalidTableStructure(tableID) }
        let rows = try table.select("tr").array().filter { row in
            var parent = row.parent()
            while let element = parent {
                if element.tagName() == "table" { return element === table }
                parent = element.parent()
            }
            return false
        }
        guard let header = rows.first else { throw CreditProgressError.invalidTableStructure(tableID) }
        let headerCells = header.children().array()
        let columns = try headerCells.map { try cellText($0) }
        guard headerCells.allSatisfy({ $0.tagName() == "th" }),
              !columns.contains(""), Set(columns).count == columns.count,
              requiredColumns.allSatisfy(columns.contains) else {
            throw CreditProgressError.invalidTableStructure(tableID)
        }
        var result: [[String: String]] = []
        var emptyMarkerSeen = false
        for row in rows.dropFirst() {
            let cells = row.children().array()
            if cells.isEmpty, try row.text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if cells.count == 1, let cell = cells.first,
               cell.tagName() == "td", try cellText(cell) == "未查询到数据",
               Int(try cell.attr("colspan")) == columns.count {
                guard result.isEmpty, !emptyMarkerSeen else { throw CreditProgressError.invalidTableStructure(tableID) }
                emptyMarkerSeen = true
                continue
            }
            guard !emptyMarkerSeen, cells.count == columns.count,
                  cells.allSatisfy({ $0.tagName() == "td" }) else {
                throw CreditProgressError.invalidTableStructure(tableID)
            }
            for cell in cells {
                for attribute in ["rowspan", "colspan"] where cell.hasAttr(attribute) {
                    guard Int(try cell.attr(attribute)) == 1 else {
                        throw CreditProgressError.invalidTableStructure(tableID)
                    }
                }
            }
            result.append(Dictionary(uniqueKeysWithValues: zip(columns, try cells.map(cellText))))
        }
        return result
    }

    private func cellText(_ cell: Element) throws -> String {
        try cell.text().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func value(in row: [String: String], column: String) -> String? {
        guard let value = row[column], !value.isEmpty else { return nil }
        return value
    }

    private func decimal(in row: [String: String], column: String) throws -> Decimal? {
        guard let text = value(in: row, column: column) else { return nil }
        guard text.utf8.count <= 38,
              text.range(of: #"\A[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil,
              let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw CreditProgressError.invalidNumber(column)
        }
        return number
    }

    private func integer(in row: [String: String], column: String) throws -> Int? {
        guard let text = value(in: row, column: column) else { return nil }
        guard text.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(text) else {
            throw CreditProgressError.invalidNumber(column)
        }
        return number
    }
}
