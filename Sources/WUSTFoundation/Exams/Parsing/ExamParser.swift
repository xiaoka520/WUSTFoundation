import Foundation
import SwiftSoup

public struct ExamParser: Sendable {
    public init() {}

    public func parse(from html: String, query: ExamQuery) throws -> ExamSchedule {
        guard !query.termID.isEmpty else { throw ExamError.invalidQuery }
        let document = try SwiftSoup.parse(html)
        let tables = try document.select("table[id=dataList]").array()
        guard !tables.isEmpty else { throw ExamError.tableNotFound }
        guard tables.count == 2 else { throw ExamError.invalidTableStructure }
        for link in try document.select("a") {
            if ["下一页", "尾页", "末页"].contains(try link.text().trimmingCharacters(in: .whitespacesAndNewlines)) {
                throw ExamError.unsupportedPagination
            }
        }
        let pageText = try document.body()?.text() ?? ""
        let regex = try NSRegularExpression(pattern: #"共\s*(\d+)\s*页"#)
        for match in regex.matches(in: pageText, range: NSRange(pageText.startIndex..., in: pageText)) {
            if let range = Range(match.range(at: 1), in: pageText), let count = Int(pageText[range]), count > 1 {
                throw ExamError.unsupportedPagination
            }
        }
        let lists = try tables.map { try parseTable($0, query: query) }
        guard Set(lists.map(\.source)) == Set<ExamArrangementSource>([.centralized, .selfRequested]) else {
            throw ExamError.invalidTableStructure
        }
        return ExamSchedule(query: query, lists: lists)
    }

    private func parseTable(_ table: Element, query: ExamQuery) throws -> ExamArrangementList {
        let rows = try table.select("tr").array().filter { row in
            var parent = row.parent()
            while let element = parent {
                if element.tagName() == "table" { return element === table }
                parent = element.parent()
            }
            return false
        }
        guard let first = rows.first else { throw ExamError.invalidTableStructure }
        let columns = try first.children().array().filter { $0.tagName() == "th" }.map {
            try $0.text().replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        }
        let required = ["学年学期", "课程编号", "课程名称", "周次", "星期", "节次", "时间", "座位号", "场地", "校区"]
        guard !columns.contains(""), Set(columns).count == columns.count,
              required.allSatisfy(columns.contains) else { throw ExamError.invalidTableStructure }
        let source: ExamArrangementSource = columns.contains("考试场次") ? .centralized : .selfRequested
        var arrangements: [ExamArrangement] = []
        var emptyMarkerSeen = false
        for row in rows.dropFirst() {
            let cells = row.children().array().filter { ["td", "th"].contains($0.tagName()) }
            if cells.isEmpty, try row.text().isEmpty { continue }
            if cells.count == 1, let cell = cells.first,
               try cell.text().trimmingCharacters(in: .whitespacesAndNewlines) == "未查询到数据",
               Int(try cell.attr("colspan")) == columns.count {
                guard arrangements.isEmpty, !emptyMarkerSeen else { throw ExamError.invalidTableStructure }
                emptyMarkerSeen = true
                continue
            }
            guard !emptyMarkerSeen, cells.count == columns.count else { throw ExamError.invalidTableStructure }
            for cell in cells {
                for name in ["rowspan", "colspan"] where cell.hasAttr(name) {
                    guard Int(try cell.attr(name)) == 1 else { throw ExamError.invalidTableStructure }
                }
            }
            let values = try cells.map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            let fields = zip(columns, values).map { ExamField(name: $0.0, value: $0.1) }
            let timeText = fields.first { $0.name == "时间" }?.value ?? ""
            let arrangement = ExamArrangement(source: source, fields: fields, timeRange: ExamTimeParser().parse(timeText))
            guard !arrangement.courseID.isEmpty, !arrangement.courseName.isEmpty, !arrangement.termID.isEmpty else {
                throw ExamError.invalidTableStructure
            }
            guard arrangement.termID == query.termID else { throw ExamError.selectionNotReflected }
            arrangements.append(arrangement)
        }
        guard emptyMarkerSeen || !arrangements.isEmpty else { throw ExamError.invalidTableStructure }
        return ExamArrangementList(source: source, columns: columns, arrangements: arrangements)
    }
}
