import Foundation
import WUSTFoundation

enum CreditProgressDemo {
    static func run(using client: WUSTLoginClient) async throws {
        log("正在读取学分完成情况……")
        let progress = try await client.fetchCreditProgress()
        show(progress.courseCategories, title: "学分类别进度")
        show(progress.generalElectives, title: "通识选修学分进度")
        if let stats = progress.pastSemesterStatistics {
            log("过往学期修读课程统计：学期数 \(text(stats.semesterCount))，已修 \(text(stats.completedCourseCount)) 门、\(text(stats.completedCredits)) 学分，学期平均 \(text(stats.averageCreditsPerSemester)) 学分。")
            log("不及格 \(text(stats.failedCourseCount)) 门、\(text(stats.failedCredits)) 学分；未选 \(text(stats.unselectedCourseCount)) 门、\(text(stats.unselectedCredits)) 学分；必修未获 \(text(stats.requiredCourseCountWithoutCredits)) 门、\(text(stats.requiredCreditsNotEarned)) 学分。")
        }
        log("培养方案课程修读明细共 \(progress.courses.count) 条。输入 1 查看，其他输入返回主菜单：")
        guard readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) == "1" else { return }
        for course in progress.courses {
            let fields = [
                course.termID ?? "未提供学期",
                course.courseID,
                course.courseName,
                "\(text(course.credits)) 学分",
                course.courseNature,
                course.courseAttribute,
                course.status
            ]
            log(fields.compactMap { $0 }.joined(separator: "｜"))
        }
    }

    private static func show(_ entries: [CreditCategoryProgress], title: String) {
        log("\(title)（\(entries.count) 项）：")
        for entry in entries {
            let label = entry.courseAttribute.map { "\(entry.name)（\($0)）" } ?? entry.name
            log("  \(label)：要求 \(text(entry.requiredCredits))，已获 \(text(entry.earnedCredits))，还差 \(text(entry.remainingCredits)) 学分。")
        }
    }

    private static func text(_ value: Decimal?) -> String {
        value.map { NSDecimalNumber(decimal: $0).stringValue } ?? "未提供"
    }

    private static func text(_ value: Int?) -> String {
        value.map { String($0) } ?? "未提供"
    }

    static func errorMessage(for error: CreditProgressError) -> String {
        switch error {
        case .invalidURL: return "学分查询地址无效。"
        case .invalidResponse: return "学分查询响应无效。"
        case .unexpectedStatusCode(let code): return "学分查询失败（HTTP \(code)）。"
        case .unexpectedRedirect: return "学分查询跳转到了非预期页面。"
        case .authenticationRequired: return "学分查询需要有效的教务会话。"
        case .invalidEncoding: return "学分完成情况页面无法按 UTF-8 解码。"
        case .tableNotFound(let table): return "未找到学分完成情况表格（\(table)）。"
        case .invalidTableStructure(let table): return "学分完成情况表格结构有变化（\(table)）。"
        case .invalidNumber(let column): return "学分完成情况的“\(column)”列含有无法识别的数值。"
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}
