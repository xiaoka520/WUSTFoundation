import Foundation
import WUSTFoundation

enum TrainingPlanDemo {
    static func run(using client: WUSTLoginClient) async throws {
        log("正在读取培养方案及完成情况……")
        let plan = try await client.fetchTrainingPlan()
        let tables = plan.blocks.compactMap { block -> TrainingPlanTable? in
            if case .table(let table) = block { return table }
            return nil
        }
        log("培养方案读取完成：\(plan.title)")
        log("共 \(plan.blocks.count) 个正文块，其中 \(tables.count) 张表格；表格保留合并单元格和空白值。")
        while true {
            log("输入 1 查看全文，2 查看表格结构与内容，其他输入返回主菜单：")
            guard let input = readLine() else { return }
            switch input.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "1":
                log(plan.text)
            case "2":
                for (index, table) in tables.enumerated() {
                    let merged = table.cells.filter { $0.rowSpan > 1 || $0.columnSpan > 1 }.count
                    log("表格 \(index + 1)：\(table.rowCount) 行 × \(table.columnCount) 列，\(table.cells.count) 个实际单元格，\(merged) 个合并单元格。")
                }
                log("请输入表格序号，其他输入返回：")
                guard let raw = readLine(),
                      let index = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                      index > 0,
                      tables.indices.contains(index - 1) else { continue }
                log(tables[index - 1].text)
                log("控制台以制表符展示；App 应使用 cells 中的坐标与跨度渲染表格。")
            default:
                return
            }
        }
    }

    static func errorMessage(for error: TrainingPlanError) -> String {
        switch error {
        case .authenticationRequired: return "培养方案查询需要有效的教务会话。"
        case .invalidURL: return "培养方案地址无效。"
        case .invalidResponse: return "培养方案响应无效。"
        case .unexpectedStatusCode(let code): return "培养方案请求失败（HTTP \(code)）。"
        case .unexpectedRedirect: return "培养方案请求被转到非预期页面。"
        case .invalidEncoding: return "培养方案页面无法按 UTF-8 解码。"
        case .planNotFound: return "页面中未找到当前支持的培养方案正文及课程表。"
        case .titleNotFound: return "培养方案缺少标题。"
        case .invalidTableStructure: return "培养方案表格结构不符合预期，未返回可能错位的数据。"
        case .contentTooLarge: return "培养方案表格大小或嵌套层数超出解析范围。"
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}
