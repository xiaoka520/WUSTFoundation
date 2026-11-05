import Foundation
import SwiftSoup

public struct NoticeDetailParser {
    public init() {}

    public func parse(
        from html: String,
        summary: NoticeSummary,
        responseURL: URL,
        datePolicy: NoticeDatePolicy = NoticeDatePolicy()
    ) throws -> NoticeDetail {
        let range = try datePolicy.resolve()
        let document = try SwiftSoup.parse(html)
        guard let body = try document.select("#vsb_content, .v_news_content, [id^=vsb_content_]").first() else {
            throw NoticeError.bodyNotFound
        }
        let title = try articleTitle(in: document, fallback: summary.title)
        let date = try publicationDate(in: document, fallback: summary.publishedDate)
        guard range.allows(date) else { throw NoticeError.filteredPublicationDate }
        let resolvedSummary = NoticeSummary(source: summary.source, title: title, url: responseURL, publishedDate: date.value)
        let paragraphs = try NoticeTextExtractor.paragraphs(from: body)
        var images: [NoticeImage] = []
        var seenImages = Set<URL>()
        for image in try body.select("img") {
            let lazySource = try image.attr("data-src")
            let path = try lazySource.isEmpty ? image.attr("src") : lazySource
            guard let url = NoticeURL.resolve(path, relativeTo: responseURL), seenImages.insert(url).inserted else { continue }
            let alt = try image.attr("alt").trimmingCharacters(in: .whitespacesAndNewlines)
            images.append(NoticeImage(url: url, alt: alt.isEmpty ? nil : alt))
        }

        var attachments: [NoticeLink] = []
        var links: [NoticeLink] = []
        var documents: [NoticeDocument] = []
        var seenAttachments = Set<URL>()
        var seenLinks = Set<URL>()
        var seenDocuments = Set<URL>()
        let attachmentScope = body.parent() ?? body
        for link in try attachmentScope.select("a[href]") {
            guard let url = NoticeURL.resolve(try link.attr("href"), relativeTo: responseURL), isAttachment(url) else { continue }
            let text = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if seenAttachments.insert(url).inserted {
                attachments.append(NoticeLink(title: text.isEmpty ? url.lastPathComponent : text, url: url))
            }
        }
        for link in try body.select("a[href]") {
            guard let url = NoticeURL.resolve(try link.attr("href"), relativeTo: responseURL),
                  !isAttachment(url), seenLinks.insert(url).inserted else { continue }
            let text = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            links.append(NoticeLink(title: text.isEmpty ? url.absoluteString : text, url: url))
        }
        var embeddedPaths: [String] = []
        for frame in try body.select("iframe[src], embed[src], object[data]") {
            let path = try frame.tagName() == "object" ? frame.attr("data") : frame.attr("src")
            embeddedPaths.append(path)
        }
        let pdfRegex = try NSRegularExpression(pattern: #"showVsbpdfIframe\(\s*["']([^"']+)["']"#)
        for script in try body.select("script") {
            let source = script.data()
            let searchRange = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in pdfRegex.matches(in: source, range: searchRange) {
                if let range = Range(match.range(at: 1), in: source) { embeddedPaths.append(String(source[range])) }
            }
        }
        for path in embeddedPaths {
            guard let url = NoticeURL.resolve(path, relativeTo: responseURL),
                  url.pathExtension.lowercased() == "pdf", seenDocuments.insert(url).inserted else { continue }
            documents.append(NoticeDocument(url: url, sourceURL: responseURL))
            if seenAttachments.insert(url).inserted {
                attachments.append(NoticeLink(title: "正文 PDF", url: url))
            }
        }
        return NoticeDetail(
            summary: resolvedSummary, text: paragraphs.joined(separator: "\n\n"), paragraphs: paragraphs,
            images: images, attachments: attachments, links: links, documents: documents
        )
    }

    private func articleTitle(in document: Document, fallback: String) throws -> String {
        for node in try document.select("meta[name=pageTitle], meta[name=ArticleTitle], meta[property=og:title]") {
            let value = try node.attr("content").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        for node in try document.select(".cotit, h1.title-center, .article-title, .news-title, h1") {
            let value = try node.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        let value = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw NoticeError.titleNotFound }
        return value
    }

    private func publicationDate(in document: Document, fallback: String) throws -> NoticeDate {
        for node in try document.select("meta[name=PubDate], meta[name=pubdate], meta[property=article:published_time]") {
            let value = try node.attr("content")
            if !value.isEmpty {
                guard let date = NoticeDate.extract(from: value) else { throw NoticeError.missingPublicationDate }
                return date
            }
        }
        for node in try document.select(".showdate, .sjkk, .article-date, .news-date, .info-date") {
            let value = try node.text()
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let date = NoticeDate.extract(from: value) else { throw NoticeError.missingPublicationDate }
                return date
            }
        }
        if let body = try document.select("#vsb_content, .v_news_content, [id^=vsb_content_]").first(),
           let parent = body.parent() {
            var preceding: [Element] = []
            for child in parent.children() {
                if child === body { break }
                preceding.append(child)
            }
            for node in preceding.reversed() {
                let value = try node.text()
                if ["发布时间", "发布日期", "浏览次数", "点击"].contains(where: { value.contains($0) }) {
                    guard let date = NoticeDate.extract(from: value) else { throw NoticeError.missingPublicationDate }
                    return date
                }
            }
        }
        guard let date = NoticeDate.parseExact(fallback) else { throw NoticeError.missingPublicationDate }
        return date
    }

    private func isAttachment(_ url: URL) -> Bool {
        url.path.hasSuffix("/download.jsp") ||
            ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "zip", "rar", "7z", "txt", "csv"].contains(url.pathExtension.lowercased())
    }
}
