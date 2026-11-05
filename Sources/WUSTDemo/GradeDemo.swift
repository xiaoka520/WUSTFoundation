import Foundation
import WUSTFoundation

enum GradeDemo {
    static func run(using client: WUSTLoginClient) async throws {
        log("正在读取成绩查询选项……")
        let options = try await client.fetchGradeQueryOptions()
        let termID = try chooseID(title: "学期", options: options.terms)
        let natureID = try chooseID(title: "课程性质", options: options.courseNatures)
        log("输入课程名称关键词，回车不限制：")
        let courseName = try readInput()
        log("输入 1 显示全部成绩（默认），2 显示最好成绩：")
        let mode = try readInput()
        guard ["", "1", "2"].contains(mode) else { throw GradeError.invalidQuery }
        log("输入 1 显示补重成绩，回车不勾选：")
        let retakes = try readInput()
        guard ["", "1"].contains(retakes) else { throw GradeError.invalidQuery }
        let query = GradeQuery(
            termID: termID.isEmpty ? nil : termID,
            courseNatureID: natureID.isEmpty ? nil : natureID,
            courseName: courseName,
            displayMode: mode == "2" ? .best : .all,
            includesRetakes: retakes == "1"
        )
        log("正在查询课程成绩……")
        let report = try await client.fetchGrades(query: query)
        guard !report.records.isEmpty else {
            log("查询完成：服务器明确返回未查询到数据。")
            return
        }
        log("查询完成，共 \(report.records.count) 条成绩记录。输入 1 查看详情，其他输入返回：")
        guard try readInput() == "1" else { return }
        for (index, record) in report.records.enumerated() {
            log("\(index + 1). \(record.courseName)（\(record.courseID)）")
            for field in record.fields where field.name != "序号" {
                log("  \(field.name)：\(field.value.isEmpty ? "（空白）" : field.value)")
            }
        }
    }

    private static func chooseID(title: String, options: [GradeOption]) throws -> String {
        while true {
            log("输入\(title) ID，回车不限制，输入 ? 查看服务器选项：")
            let value = try readInput()
            if value == "?" {
                for option in options {
                    if option.id.isEmpty { log("（空 ID）\(option.name)") }
                    else if option.id == option.name { log(option.name) }
                    else { log("\(option.id)  \(option.name)") }
                }
                continue
            }
            guard options.contains(where: { $0.id == value }) else {
                log("请选择服务器提供的 ID。")
                continue
            }
            return value
        }
    }

    static func errorMessage(for error: GradeError) -> String {
        switch error {
        case .invalidURL: return "成绩查询地址无效。"
        case .invalidResponse: return "成绩查询响应无效。"
        case .unexpectedStatusCode(let code): return "成绩查询失败（HTTP \(code)）。"
        case .unexpectedRedirect: return "成绩查询跳转到了非预期页面。"
        case .authenticationRequired: return "成绩查询需要有效的教务会话。"
        case .invalidEncoding: return "成绩页面无法按 UTF-8 解码。"
        case .formNotFound: return "未找到成绩查询表单。"
        case .unsupportedForm: return "成绩查询表单或提交协议不符合预期。"
        case .invalidQuery: return "成绩查询条件无效，请选择服务器提供的选项。"
        case .invalidFormEncoding: return "成绩查询参数编码失败。"
        case .tableNotFound: return "未找到成绩表格。"
        case .invalidTableStructure: return "成绩表格结构不符合预期，未返回可能错位的数据。"
        case .unsupportedPagination: return "检测到成绩分页，本版尚未支持该分页结构。"
        case .selectionNotReflected: return "返回成绩的开课学期与请求不一致。"
        }
    }

    private static func readInput() throws -> String {
        guard let input = readLine() else { throw WUSTDemo.DemoError.missingInput }
        return input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}
