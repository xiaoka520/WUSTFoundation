import Foundation

public struct TrainingPlanTable: Codable, Hashable, Sendable {
    public let caption: String?
    public let rowCount: Int
    public let columnCount: Int
    public let cells: [TrainingPlanCell]

    public init(caption: String?, rowCount: Int, columnCount: Int, cells: [TrainingPlanCell]) {
        self.caption = caption
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.cells = cells
    }

    public func cell(atRow row: Int, column: Int) -> TrainingPlanCell? {
        guard row >= 0, row < rowCount, column >= 0, column < columnCount else { return nil }
        return cells.first {
            row >= $0.row && row - $0.row < $0.rowSpan &&
                column >= $0.column && column - $0.column < $0.columnSpan
        }
    }

    public var text: String {
        var lines: [String] = []
        if let caption, !caption.isEmpty { lines.append(caption) }
        for row in 0..<max(0, rowCount) {
            let values = (0..<max(0, columnCount)).map { column in
                guard let cell = cell(atRow: row, column: column),
                      cell.row == row, cell.column == column else { return "" }
                return cell.text.replacingOccurrences(of: "\n", with: " ")
            }
            lines.append(values.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }
}

public struct TrainingPlanCell: Codable, Hashable, Sendable {
    public let row: Int
    public let column: Int
    public let rowSpan: Int
    public let columnSpan: Int
    public let isHeader: Bool
    public let blocks: [TrainingPlanBlock]

    public init(
        row: Int,
        column: Int,
        rowSpan: Int = 1,
        columnSpan: Int = 1,
        isHeader: Bool = false,
        blocks: [TrainingPlanBlock]
    ) {
        self.row = row
        self.column = column
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
        self.isHeader = isHeader
        self.blocks = blocks
    }

    public var text: String {
        blocks.map(\.text).joined(separator: "\n\n")
    }
}
