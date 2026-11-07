import Foundation
import WUSTFoundation

enum CampusShuttleDemo {
    static func run(using client: WUSTLoginClient) async throws {
        log("正在读取门户校车时刻表……")
        let schedule = try await client.fetchCampusShuttleSchedule()
        log("\(schedule.title)（\(schedule.departures.count) 班）")

        var previousHeading: String?
        for departure in schedule.departures {
            let heading = "\(departure.operatingDays) · \(departure.origin) → \(departure.destination)"
            if heading != previousHeading {
                log("\n\(heading)")
                previousHeading = heading
            }
            log("  \(departure.departureTime)  \(departure.route)")
        }
        for note in schedule.notes {
            log("\n\(note)")
        }
    }

    static func errorMessage(for error: CampusShuttleError) -> String {
        switch error {
        case .authenticationRequired: return "门户未接受当前登录会话，无法读取校车时刻表。"
        case .unexpectedStatusCode(let code): return "门户校车查询失败（HTTP \(code)）。"
        case .rejected(let code): return "门户拒绝校车查询（业务码 \(code)）。"
        case .invalidResponse: return "门户校车接口响应无效。"
        case .invalidSchedule: return "门户校车表格格式无法识别。"
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}
