import Foundation
import WUSTFoundation

enum ExamDemo {
    static func run(using client: WUSTLoginClient) async throws {
        log("正在读取考试安排查询选项……")
        let options = try await client.fetchExamQueryOptions()
        let termID = try chooseID(title: "学年学期", options: options.terms, defaultID: options.selectedTermID)
        let categoryID = try chooseID(title: "学期类别", options: options.categories, defaultID: options.selectedCategoryID ?? "")
        let query = ExamQuery(termID: termID, categoryID: categoryID.isEmpty ? nil : categoryID)
        log("正在查询考试安排……")
        let schedule = try await client.fetchExamSchedule(query: query)
        for list in schedule.lists {
            log("\(list.source.name)：\(list.arrangements.count) 条。")
        }
        guard !schedule.arrangements.isEmpty else {
            log("服务器已明确返回两类考试均未查询到数据。")
            return
        }
        log("输入 1 查看考试详情，其他输入返回主菜单：")
        guard try readInput() == "1" else { return }
        for list in schedule.lists {
            log("\(list.source.name)：")
            for (index, exam) in list.arrangements.enumerated() {
                log("\(index + 1). \(exam.courseName)（\(exam.courseID)）")
                for field in exam.fields where field.name != "序号" {
                    log("  \(field.name)：\(field.value.isEmpty ? "（空白）" : field.value)")
                }
                log(exam.timeRange == nil ? "  暂无可转换的明确起止时间，保留网页原文。" : "  已转换为上海时区的明确起止时间。")
            }
        }
    }

    private static func chooseID(title: String, options: [ExamOption], defaultID: String?) throws -> String {
        while true {
            let defaultName = options.first { $0.id == defaultID }?.name
            let prompt = defaultName.map { "回车使用“\($0)”" } ?? "没有明确默认值，请填写 ID"
            log("请输入\(title) ID，\(prompt)，输入 ? 查看选项：")
            let input = try readInput()
            if input == "?" {
                for option in options {
                    if option.id.isEmpty { log("（空 ID）\(option.name)") }
                    else if option.id == option.name { log(option.name) }
                    else { log("\(option.id)  \(option.name)") }
                }
                continue
            }
            let id = input.isEmpty ? (defaultID ?? "") : input
            guard options.contains(where: { $0.id == id }) else {
                log("请选择服务器提供的 ID。")
                continue
            }
            return id
        }
    }

    static func errorMessage(for error: ExamError) -> String {
        switch error {
        case .invalidURL: return "考试安排查询地址无效。"
        case .invalidResponse: return "考试安排响应无效。"
        case .unexpectedStatusCode(let code): return "考试安排请求失败（HTTP \(code)）。"
        case .unexpectedRedirect: return "考试安排请求跳转到了非预期页面。"
        case .authenticationRequired: return "考试安排查询需要有效的教务会话。"
        case .invalidEncoding: return "考试安排页面无法按 UTF-8 解码。"
        case .formNotFound: return "未找到考试安排查询表单。"
        case .unsupportedForm: return "考试安排表单或提交协议不符合预期。"
        case .invalidQuery: return "考试安排查询条件无效。"
        case .invalidFormEncoding: return "考试安排查询参数编码失败。"
        case .tableNotFound: return "未找到考试安排表格。"
        case .invalidTableStructure: return "考试安排双表结构不符合预期，未返回可能错位的数据。"
        case .unsupportedPagination: return "检测到考试安排分页，本版尚未支持该分页结构。"
        case .selectionNotReflected: return "考试安排返回的学期与请求不一致。"
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
