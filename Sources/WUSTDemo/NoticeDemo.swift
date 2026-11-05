import Foundation
import WUSTFoundation

enum NoticeDemo {
    static func run() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let service = NoticeService()
        while let source = try chooseSource() {
            do {
                var page = try await service.fetchPage(source: source, using: session)
                while true {
                    show(page)
                    log("输入通知序号查看正文，n 下一页，p 上一页，其他输入返回来源选择：")
                    let input = try readInput()
                    if input == "n" || input == "p" {
                        let url = input == "n" ? page.nextPageURL : page.previousPageURL
                        guard let url else { log("没有对应的分页链接。"); continue }
                        page = try await service.fetchPage(source: source, at: url, using: session)
                    } else if let index = Int(input), index >= 1, index <= page.items.count {
                        do {
                            try await showDetail(page.items[index - 1], service: service, session: session)
                        } catch {
                            if error is CancellationError { throw error }
                            log(errorMessage(for: error))
                        }
                    } else {
                        break
                    }
                }
            } catch {
                if error is CancellationError { throw error }
                log(errorMessage(for: error))
            }
        }
    }

    static func errorMessage(for error: any Error) -> String {
        if let error = error as? URLError { return "通知请求遇到网络错误（URLError \(error.code.rawValue)）。" }
        guard let error = error as? NoticeError else { return "通知解析未完成，错误类型：\(String(reflecting: type(of: error)))。" }
        switch error {
        case .invalidURL, .unsupportedURL: return "该地址不在当前通知接口支持的页面范围内，请查看原文。"
        case .invalidResponse: return "通知站点返回了无效响应。"
        case .unexpectedStatusCode(let code): return "通知请求失败（HTTP \(code)）。"
        case .unexpectedRedirect: return "通知跳转到了非预期页面。"
        case .authenticationRequired: return "该通知需要学校身份认证，请通过原文入口登录查看；本演示不自动登录。"
        case .invalidEncoding: return "通知页面编码无法识别。"
        case .listNotFound: return "没有识别到通知列表，不将此响应当作正常空列表。"
        case .titleNotFound: return "没有识别到通知标题。"
        case .bodyNotFound: return "没有识别到通知正文。"
        case .missingPublicationDate: return "通知没有可识别的有效发布日期，已拒绝返回。"
        case .filteredPublicationDate: return "通知发布日期被当前规则排除，已拒绝返回正文。"
        case .invalidDatePolicy: return "日期过滤配置无效。"
        case .invalidConfiguration: return "PDF 下载的容量配置无效。"
        case .invalidDocument: return "服务器没有返回可识别的 PDF 原文件。"
        case .documentTooLarge: return "PDF 原文件超过当前允许的容量，未截取或返回部分文件。"
        }
    }

    private static func chooseSource() throws -> NoticeSource? {
        log("公开通知无需教务登录。默认只排除 1980-01-01 和无效日期，未来日期正常保留。")
        for (index, source) in NoticeSource.allCases.enumerated() { log("\(index + 1). \(source.name)") }
        log("输入来源序号，其他输入结束通知演示：")
        guard let index = Int(try readInput()), index >= 1, index <= NoticeSource.allCases.count else { return nil }
        return NoticeSource.allCases[index - 1]
    }

    private static func show(_ page: NoticePage) {
        log("\(page.source.name)：第 \(page.currentPage.map(String.init) ?? "未知") / \(page.totalPages.map(String.init) ?? "未知") 页。")
        for (index, item) in page.items.enumerated() { log("\(index + 1). [\(item.publishedDate)] \(item.title)") }
        log("本页返回 \(page.items.count) 条，日期规则排除 \(page.filteredItemCount) 条。")
        if page.items.isEmpty { log("本页没有符合规则的通知；是否还有下一页以分页链接为准。") }
    }

    private static func showDetail(_ item: NoticeSummary, service: NoticeService, session: URLSession) async throws {
        log("正在读取纯文本正文及原始 PDF 链接……")
        let detail = try await service.fetchDetail(item, using: session)
        log("\(detail.summary.title)\n发布日期：\(detail.summary.publishedDate)\n原文：\(detail.summary.url.absoluteString)")
        if detail.hasText {
            log(String(detail.text.prefix(2000)))
            if detail.text.count > 2000 { log("当前展示前 2000 字符；输入 1 可显示完整纯文本。") }
        } else {
            log("网页没有纯文本正文，请查看原始 PDF、图片或附件。")
        }
        for document in detail.documents { log("原始 PDF：\(document.url.absoluteString)") }
        log("图片 \(detail.images.count) 张；附件 \(detail.attachments.count) 个。")
        while true {
            log("输入 1 显示网页完整纯文本，2 查看资源链接，3 原版快速预览 PDF，其他输入返回列表：")
            switch try readInput() {
            case "1": log(detail.hasText ? detail.text : "没有可提取的正文文字。")
            case "2":
                for image in detail.images { log("图片：\(image.url.absoluteString)") }
                for attachment in detail.attachments { log("附件：\(attachment.title)  \(attachment.url.absoluteString)") }
                for link in detail.links { log("链接：\(link.title)  \(link.url.absoluteString)") }
            case "3":
                guard !detail.documents.isEmpty else { log("这条通知没有内嵌 PDF。"); continue }
                for (index, document) in detail.documents.enumerated() { log("\(index + 1). \(document.url.lastPathComponent)") }
                log("请输入 PDF 序号，回车选择第一份：")
                let input = try readInput()
                let index = input.isEmpty ? 1 : (Int(input) ?? 0)
                guard index >= 1, index <= detail.documents.count else { log("PDF 序号无效。"); continue }
                try await NoticePDFPreview.show(detail.documents[index - 1], service: service, session: session)
                log("已发起 macOS 原版快速预览；可在预览窗口中查看完整 PDF。")
            default: return
            }
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
