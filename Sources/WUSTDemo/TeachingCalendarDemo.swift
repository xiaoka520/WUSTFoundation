import Foundation
import WUSTFoundation

enum TeachingCalendarDemo {
    static func run(using client: WUSTLoginClient) async throws {
        var calendar = try await calibrate(using: client)
        while true {
            log("输入 1 查看某周的日期范围，2 查询某个日期属于哪周，3 重新向服务器校准，其他输入返回主菜单：")
            switch try readInput() {
            case "1":
                log("请输入教学周（1～\(calendar.totalWeeks)）：")
                guard let week = Int(try readInput()), week >= 1, week <= calendar.totalWeeks else {
                    log("教学周超出已校准范围。")
                    continue
                }
                show(try calendar.range(ofWeek: week))
            case "2":
                let date = try chooseDate(allowToday: false)
                if let week = try calendar.week(containing: date) {
                    log("\(date.yyyyMMdd) 属于第 \(week) 周。")
                    show(try calendar.range(ofWeek: week))
                } else {
                    log("该日期不在本次已校准的时间范围内；需要查询其他学期时，请重新向服务器校准。")
                }
            case "3":
                calendar = try await calibrate(using: client)
            default:
                return
            }
        }
    }

    private static func calibrate(using client: WUSTLoginClient) async throws -> TeachingCalendar {
        let date = try chooseDate(allowToday: true)
        log("正在请求服务器确认 \(date.yyyyMMdd) 对应的教学周……")
        let calendar = try await client.fetchTeachingCalendar(on: date)
        log("服务器校准成功：\(calendar.referenceDate.yyyyMMdd)，第 \(calendar.referenceWeek) 周 / 共 \(calendar.totalWeeks) 周。")
        log("本次日期范围：\(calendar.firstMonday.yyyyMMdd)～\(calendar.lastSunday.yyyyMMdd)。")
        show(try calendar.range(ofWeek: calendar.referenceWeek))
        log("后续日期换算在本地完成，不再发送网络请求；这里不包含调休后的实际课程调整。")
        return calendar
    }

    private static func chooseDate(allowToday: Bool) throws -> AcademicDate {
        while true {
            log(allowToday ? "请输入校准日期（yyyyMMdd），回车使用上海时区的今天：" : "请输入日期（yyyyMMdd）：")
            let input = try readInput()
            if allowToday && input.isEmpty { return try AcademicDate.today() }
            do {
                return try AcademicDate(yyyyMMdd: input)
            } catch TimetableError.invalidDate {
                log("日期无效，例如 20261105 表示 2026 年 11 月 5 日。")
            }
        }
    }

    private static func show(_ week: TeachingWeek) {
        log("第 \(week.number) 周：\(week.startDate.yyyyMMdd)（周一）～\(week.endDate.yyyyMMdd)（周日）。")
    }

    private static func readInput() throws -> String {
        guard let value = readLine() else { throw WUSTDemo.DemoError.missingInput }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}
