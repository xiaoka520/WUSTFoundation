import Foundation
import WUSTFoundation

enum LibraryDemo {
    static func run(using client: WUSTLoginClient) async throws {
        log("正在读取图书馆账户统计……")
        let statistics = try await client.fetchLibraryStatistics()
        let fineSum = statistics.fineSum.map { NSDecimalNumber(decimal: $0).stringValue }
        log("当前借阅：\(display(statistics.loanCount))")
        log("即将到期：\(display(statistics.expireCount))")
        log("滞纳金｜违章：\(fineSum ?? "未提供")")
        log("我的请求：\(display(statistics.requestCount))")
        log("我的书单：\(display(statistics.booklistCount))")

        while true {
            log("输入 1 查看当前借阅，2 查看即将到期，3 查看滞纳金｜违章，4 查看我的请求，5 查看我的书单，其他输入返回：")
            switch readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "1":
                showLoans(try await client.fetchLibraryCurrentLoans())
            case "2":
                showLoans(try await client.fetchLibraryOverdueSoon())
            case "3":
                log("账户滞纳金：\(fineSum ?? "未提供")")
                showRecords(try await client.fetchLibraryFines())
            case "4":
                showRecords(try await client.fetchLibraryRequests())
            case "5":
                try await showBooklists(using: client)
            default:
                return
            }
        }
    }

    private static func showLoans(_ page: LibraryPage<LibraryLoan>) {
        log("第 \(page.currentPage) 页，共 \(page.totalItems) 条。")
        for loan in page.items {
            log("  \(loan.title ?? "书名缺失")（应还日期 \(loan.dueDate ?? "未提供")）")
        }
    }

    private static func showRecords(_ page: LibraryPage<LibraryRecord>) {
        log("第 \(page.currentPage) 页，共 \(page.totalItems) 条。")
        for (index, record) in page.items.enumerated() {
            log("  第 \(index + 1) 条的字段为 \(record.keys.sorted().joined(separator: "、"))。")
        }
    }

    private static func showBooklists(using client: WUSTLoginClient) async throws {
        let booklists = try await client.fetchLibraryBooklists()
        log("共返回 \(booklists.count) 项书单。")
        guard !booklists.isEmpty else { return }
        for (index, booklist) in booklists.enumerated() {
            log("  \(index + 1). \(booklist.name ?? "未命名")")
        }
        log("输入序号查看书单内的书目，回车返回：")
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              let selection = Int(input), (1...booklists.count).contains(selection) else { return }
        guard let id = booklists[selection - 1].id else { throw LibraryError.invalidBooklistID }
        showRecords(try await client.fetchLibraryBooklistBooks(id: id))
    }

    private static func display(_ value: Int?) -> String {
        value.map { String($0) } ?? "未提供"
    }

    static func errorMessage(for error: LibraryError) -> String {
        switch error {
        case .invalidURL: return "图书馆请求地址无效。"
        case .invalidResponse: return "图书馆返回了无效响应。"
        case .unexpectedStatusCode(let code): return "图书馆请求失败（HTTP \(code)）。"
        case .unexpectedRedirect: return "图书馆请求跳转到非预期地址。"
        case .authenticationRequired: return "图书馆会话未建立或已失效。"
        case .invalidEncoding: return "图书馆响应编码无效。"
        case .invalidPayload: return "图书馆响应结构无法识别。"
        case .invalidPagination: return "图书馆分页参数无效。"
        case .invalidBooklistID: return "图书馆书单 ID 无效。"
        case .serviceRejected(let code): return "图书馆业务接口拒绝请求（业务码 \(code)）。"
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}
