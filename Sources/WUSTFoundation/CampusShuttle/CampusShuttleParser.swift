import Foundation
import SwiftSoup

struct CampusShuttleParser {
    func parse(_ html: String) throws -> CampusShuttleSchedule {
        let document = try SwiftSoup.parseBodyFragment(html)
        guard let body = document.body(),
              let table = try body.select("table").first() else {
            throw CampusShuttleError.invalidSchedule
        }
        let grid: TrainingPlanTable
        do {
            grid = try TrainingPlanTableParser().parse(table, depth: 0)
        } catch is TrainingPlanError {
            throw CampusShuttleError.invalidSchedule
        }

        let headers = ["日期", "起点", "终点", "发车时间", "行车线路"]
        guard grid.columnCount == headers.count,
              let headerRow = (0..<grid.rowCount).first(where: { row in
                  headers.enumerated().allSatisfy { column, label in
                      guard let cell = grid.cell(atRow: row, column: column),
                            cell.row == row, cell.columnSpan == 1 else { return false }
                      return cell.text.filter { !$0.isWhitespace } == label
                  }
              }) else {
            throw CampusShuttleError.invalidSchedule
        }

        let title = grid.cells.first {
            $0.row < headerRow && $0.columnSpan == headers.count && !$0.text.isEmpty
        }?.text ?? grid.caption ?? "校车时刻表"
        var departures: [CampusShuttleDeparture] = []
        var notes: [String] = []
        for row in (headerRow + 1)..<grid.rowCount {
            if let cell = grid.cell(atRow: row, column: 0), cell.columnSpan == headers.count {
                if cell.row == row, !cell.text.isEmpty { notes.append(cell.text) }
                continue
            }

            let values = headers.indices.map { grid.cell(atRow: row, column: $0)?.text ?? "" }
            if values[3].isEmpty && values[4].isEmpty { continue }
            guard values.allSatisfy({ !$0.isEmpty }),
                  values[3].range(
                      of: #"\A(?:[01]?[0-9]|2[0-3])[:：][0-5][0-9]\z"#,
                      options: .regularExpression
                  ) != nil else {
                throw CampusShuttleError.invalidSchedule
            }
            departures.append(CampusShuttleDeparture(
                operatingDays: values[0], origin: values[1], destination: values[2],
                departureTime: values[3].replacingOccurrences(of: "：", with: ":"), route: values[4]
            ))
        }

        guard !departures.isEmpty else { throw CampusShuttleError.invalidSchedule }
        try table.remove()
        notes += try NoticeTextExtractor.paragraphs(from: body)
        return CampusShuttleSchedule(title: title, departures: departures, notes: notes)
    }
}
