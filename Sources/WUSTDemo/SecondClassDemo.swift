import Foundation
import WUSTFoundation

enum SecondClassDemo {
    static func run(using client: WUSTLoginClient) async throws {
        log("正在读取第二课堂成绩单……")
        let transcript = try await client.fetchSecondClassTranscript()
        log("素质发展总学分 \(text(transcript.earnedCredits))，评价 \(transcript.evaluation)")
        if transcript.categories.isEmpty { log("当前没有要求学分大于 0 的项目。") }
        for category in transcript.categories {
            log("\n\(category.name)（要求 \(text(category.requiredCredits)) 学分）")
            for item in category.requirements {
                let kind = item.kind == .required ? "必修" : "选修"
                log("  \(kind)  \(text(item.earnedCredits))/\(text(item.requiredCredits)) 分，\(item.isCompleted ? "已达成" : "未完成")")
            }
        }
    }

    static func errorMessage(for error: SecondClassError) -> String {
        switch error {
        case .authenticationRequired: return "学工系统应用初始化或成绩查询仍未通过认证。"
        case .ticketExchangeRejected(let code): return "学工系统 ST 回调未通过认证（HTTP \(code)）。"
        case .unexpectedStatusCode(let code): return "第二课堂请求失败（HTTP \(code)）。"
        case .unexpectedRedirect: return "第二课堂跳转到了非预期地址。"
        case .rejected(let code):
            let safe = code.range(of: #"\A[A-Za-z0-9_-]{1,32}\z"#, options: .regularExpression) != nil ? code : "未知"
            return "第二课堂拒绝查询（业务码 \(safe)）。"
        case .invalidResponse: return "第二课堂成绩单响应格式无法识别。"
        }
    }

    private static func text(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}
