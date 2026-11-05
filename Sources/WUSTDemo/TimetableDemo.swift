import Foundation
import WUSTFoundation

enum TimetableDemo {
    private static let maxWeek = 30
    private static let maxSection = 12

    static func run(using client: WUSTLoginClient) async throws {
        log("正在通过当前登录会话读取学期列表……")
        let terms = try await client.fetchAcademicTerms()
        let term = try chooseTerm(from: terms)

        log("正在获取并解析 \(term.name) 的整学期课表……")
        let timetable = try await client.fetchTimetable(
            term: term,
            maxWeek: maxWeek,
            maxSection: maxSection
        )
        log("课表解析完成：\(timetable.term.name)，共 \(timetable.meetings.count) 条课程安排。")
        log("同一课程在不同星期、节次、周次或地点的安排可能分别计数。")
        guard !timetable.meetings.isEmpty else {
            log("当前学期课表为空。")
            return
        }

        while true {
            log("输入 1 查看全部安排，2 按教学周和星期筛选，其他输入返回主菜单：")
            switch try readInput() {
            case "1":
                show(timetable.meetings)
            case "2":
                let week = try chooseWeek()
                let weekday = try chooseWeekday()
                let meetings: [CourseMeeting]
                if let weekday {
                    meetings = timetable.meetings(inWeek: week, on: weekday)
                    log("第 \(week) 周，\(weekdayName(weekday))：")
                } else {
                    meetings = timetable.meetings(inWeek: week)
                    log("第 \(week) 周：")
                }
                show(meetings)
            default:
                return
            }
        }
    }

    static func errorMessage(for error: TimetableError) -> String {
        switch error {
        case .invalidNumberList:
            return "课表中的周次或节次超出解析范围，或数字列表格式无效。"
        case .invalidTimeFormat:
            return "课表包含尚未支持的时间格式，或课程块中存在多组时间。"
        case .missingCourseName:
            return "非空课程块缺少课程名称。"
        case .missingCourseTime:
            return "课程块缺少周次与节次。"
        case .tableNotFound:
            return "响应中没有找到课表，不能将其当作空课表。"
        case .invalidTableStructure:
            return "课表或学期选项的页面结构不符合预期。"
        case .invalidURL:
            return "课表请求地址无效。"
        case .invalidFormEncoding:
            return "课表查询表单编码失败。"
        case .formNotFound:
            return "响应中没有找到课表查询表单。"
        case .unsupportedForm:
            return "课表表单的提交方式、地址或必要字段不符合预期。"
        case .invalidResponse:
            return "课表服务器返回了无效响应。"
        case .unexpectedStatusCode(let code):
            return "课表请求失败（HTTP \(code)）。"
        case .invalidEncoding:
            return "课表页面无法按 UTF-8 解码。"
        case .unexpectedRedirect:
            return "课表请求跳转到了非预期地址，未尝试自动恢复。"
        case .authenticationRequired:
            return "课表请求仍要求认证；本次自动恢复重试已结束。"
        case .invalidTerm:
            return "所选学期已不在服务器提供的选项中，请重新读取学期列表。"
        case .selectionNotReflected:
            return "服务器返回的学期、周次或模板与提交条件不一致，未返回这份课表。"
        case .invalidDate:
            return "日期无效，请使用真实存在的 yyyyMMdd 日期。"
        case .teachingWeekNotFound:
            return "服务器片段中没有可读取的教学周标签，暂不能校准；可能是学期外日期或页面格式变化。"
        case .invalidTeachingWeek:
            return "教学周或总周数无效、相互冲突，或查询周次超出已校准范围。"
        }
    }

    private static func chooseTerm(from list: AcademicTermList) throws -> AcademicTerm {
        log("服务器提供 \(list.terms.count) 个学期选项，页面选中学期：\(list.selectedTermID ?? "未明确")。")
        while true {
            log("输入学期 ID；回车使用页面选中学期，输入 ? 查看全部选项：")
            let input = try readInput()
            if input == "?" {
                for term in list.terms {
                    log("\(term.id)  \(term.name)")
                }
                continue
            }
            let id = input.isEmpty ? (list.selectedTermID ?? "") : input
            if let term = list.terms.first(where: { $0.id == id }) {
                return term
            }
            log("请选择服务器提供的学期 ID。")
        }
    }

    private static func chooseWeek() throws -> Int {
        while true {
            log("请输入教学周（1～\(maxWeek)）：")
            if let week = Int(try readInput()), (1...maxWeek).contains(week) {
                return week
            }
            log("教学周输入无效。")
        }
    }

    private static func chooseWeekday() throws -> Weekday? {
        while true {
            log("请输入星期（1～7）；回车查看整周：")
            let input = try readInput()
            if input.isEmpty { return nil }
            if let value = Int(input), let weekday = Weekday(rawValue: value) {
                return weekday
            }
            log("星期输入无效。")
        }
    }

    private static func show(_ meetings: [CourseMeeting]) {
        guard !meetings.isEmpty else {
            log("没有符合条件的课程安排。")
            return
        }
        for (index, meeting) in meetings.enumerated() {
            let weeks = meeting.weeks.map { String($0) }.joined(separator: ",")
            let sections = meeting.sections.map { String($0) }.joined(separator: ",")
            log("\(index + 1). \(meeting.name)")
            log("   \(weekdayName(meeting.weekday))；节次：\(sections)；周次：\(weeks)")
            log("   地点：\(meeting.location ?? "未提供")")
        }
        log("共 \(meetings.count) 条课程安排。")
    }

    private static func weekdayName(_ weekday: Weekday) -> String {
        switch weekday {
        case .monday: return "星期一"
        case .tuesday: return "星期二"
        case .wednesday: return "星期三"
        case .thursday: return "星期四"
        case .friday: return "星期五"
        case .saturday: return "星期六"
        case .sunday: return "星期日"
        }
    }

    private static func readInput() throws -> String {
        guard let value = readLine() else { throw WUSTDemo.DemoError.missingInput }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}
