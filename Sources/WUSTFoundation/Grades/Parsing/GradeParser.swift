import Foundation
import SwiftSoup

public struct GradeParser: Sendable {
    public init() {}

    public func parse(from html: String, query: GradeQuery = GradeQuery()) throws -> GradeReport {
        let document = try SwiftSoup.parse(html)
        guard let table = try document.getElementById("dataList") else { throw GradeError.tableNotFound }
        let rows = try table.select("tr").array().filter { row in
            var parent = row.parent()
            while let node = parent {
                if node.tagName() == "table" { return node === table }
                parent = node.parent()
            }
            return false
        }
        guard let header = rows.first else { throw GradeError.invalidTableStructure }
        let headerCells = header.children().array().filter { $0.tagName() == "th" }
        let columns = try headerCells.map {
            try $0.text().replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        }
        guard !columns.contains(""), Set(columns).count == columns.count,
              ["开课学期", "课程编号", "课程名称", "成绩"].allSatisfy(columns.contains) else {
            throw GradeError.invalidTableStructure
        }
        let links = try document.select("a").array()
        if try links.contains(where: { ["下一页", "尾页", "末页"].contains(try $0.text().trimmingCharacters(in: .whitespacesAndNewlines)) }) {
            throw GradeError.unsupportedPagination
        }
        let pageText = try document.body()?.text() ?? ""
        let pagePattern = try NSRegularExpression(pattern: #"共\s*(\d+)\s*页"#)
        for match in pagePattern.matches(in: pageText, range: NSRange(pageText.startIndex..., in: pageText)) {
            if let range = Range(match.range(at: 1), in: pageText),
               let count = Int(pageText[range]), count > 1 {
                throw GradeError.unsupportedPagination
            }
        }

        var records: [GradeRecord] = []
        var emptyMarkerSeen = false
        for row in rows.dropFirst() {
            let cells = row.children().array().filter { ["td", "th"].contains($0.tagName()) }
            if cells.isEmpty, try row.text().isEmpty { continue }
            if cells.count == 1, let cell = cells.first,
               try cell.text().trimmingCharacters(in: .whitespacesAndNewlines) == "未查询到数据",
               Int(try cell.attr("colspan")) == columns.count {
                guard !emptyMarkerSeen, records.isEmpty else { throw GradeError.invalidTableStructure }
                emptyMarkerSeen = true
                continue
            }
            guard !emptyMarkerSeen, cells.count == columns.count else { throw GradeError.invalidTableStructure }
            for cell in cells {
                for attribute in ["colspan", "rowspan"] where cell.hasAttr(attribute) {
                    guard Int(try cell.attr(attribute)) == 1 else { throw GradeError.invalidTableStructure }
                }
            }
            let values = try cells.map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            let fields = zip(columns, values).map { GradeField(name: $0.0, value: $0.1) }
            let record = GradeRecord(fields: fields)
            guard !record.termID.isEmpty, !record.courseID.isEmpty, !record.courseName.isEmpty else {
                throw GradeError.invalidTableStructure
            }
            if let termID = query.termID, !termID.isEmpty, record.termID != termID {
                throw GradeError.selectionNotReflected
            }
            records.append(record)
        }
        guard emptyMarkerSeen || !records.isEmpty else { throw GradeError.invalidTableStructure }
        return GradeReport(query: query, columns: columns, records: records)
    }
}
