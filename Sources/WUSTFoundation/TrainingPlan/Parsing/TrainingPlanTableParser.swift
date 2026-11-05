import Foundation
import SwiftSoup

struct TrainingPlanTableParser {
    func parse(_ table: Element, depth: Int) throws -> TrainingPlanTable {
        guard depth <= 16 else { throw TrainingPlanError.contentTooLarge }
        let rows = try table.select("tr").array().filter { row in
            var parent = row.parent()
            while let current = parent {
                if current.tagName() == "table" {
                    return current === table
                }
                parent = current.parent()
            }
            return false
        }
        guard !rows.isEmpty else { throw TrainingPlanError.invalidTableStructure }
        guard rows.count <= 4096 else { throw TrainingPlanError.contentTooLarge }
        var occupied = Set<Int>()
        var cells: [TrainingPlanCell] = []
        var columnCount = 0

        for (rowIndex, row) in rows.enumerated() {
            var column = 0
            let rowGroup = row.parent()
            let remainingGroupRows = rows[rowIndex...].prefix { $0.parent() === rowGroup }.count
            let elements = row.children().array().filter { ["td", "th"].contains($0.tagName()) }
            for element in elements {
                while column < 256, occupied.contains(rowIndex * 256 + column) { column += 1 }
                let rowSpan = try span("rowspan", in: element, remainingRows: remainingGroupRows)
                let columnSpan = try span("colspan", in: element, remainingRows: nil)
                guard rowSpan <= remainingGroupRows else {
                    throw TrainingPlanError.invalidTableStructure
                }
                guard column < 256, columnSpan <= 256 - column else {
                    throw TrainingPlanError.contentTooLarge
                }
                guard rowSpan * columnSpan <= 262_144 - occupied.count else {
                    throw TrainingPlanError.contentTooLarge
                }
                for coveredRow in rowIndex..<(rowIndex + rowSpan) {
                    for coveredColumn in column..<(column + columnSpan) {
                        guard occupied.insert(coveredRow * 256 + coveredColumn).inserted else {
                            throw TrainingPlanError.invalidTableStructure
                        }
                    }
                }
                let blocks = try TrainingPlanContentParser().parse(element.getChildNodes(), depth: depth)
                cells.append(TrainingPlanCell(
                    row: rowIndex,
                    column: column,
                    rowSpan: rowSpan,
                    columnSpan: columnSpan,
                    isHeader: element.tagName() == "th",
                    blocks: blocks
                ))
                column += columnSpan
                columnCount = max(columnCount, column)
            }
        }
        guard columnCount > 0 else { throw TrainingPlanError.invalidTableStructure }
        let caption = try table.children().array().first(where: { $0.tagName() == "caption" })?.text()
        return TrainingPlanTable(caption: caption, rowCount: rows.count, columnCount: columnCount, cells: cells)
    }

    private func span(_ attribute: String, in element: Element, remainingRows: Int?) throws -> Int {
        guard element.hasAttr(attribute) else { return 1 }
        let raw = try element.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(raw), value >= 0 else { throw TrainingPlanError.invalidTableStructure }
        if value == 0, let remainingRows { return remainingRows }
        guard value > 0 else { throw TrainingPlanError.invalidTableStructure }
        return value
    }
}
