import Foundation
import SwiftSoup

public struct NoticeListParser {
    public init() {}

    public func parse(
        from html: String,
        source: NoticeSource,
        sourceURL: URL,
        datePolicy: NoticeDatePolicy = NoticeDatePolicy()
    ) throws -> NoticePage {
        guard NoticeURL.isList(sourceURL, source: source) else { throw NoticeError.unsupportedURL }
        let range = try datePolicy.resolve()
        let document = try SwiftSoup.parse(html)
        var rows = try document.select(".news_list_date li, .new_list .liebiao li").array()
        if rows.isEmpty {
            rows = try document.select("li").array()
        }
        var items: [NoticeSummary] = []
        var seen = Set<URL>()
        var recognizedRows = 0
        var filteredCount = 0
        for row in rows {
            var article: (element: Element, url: URL)?
            for link in try row.select("a[href]") {
                if let url = NoticeURL.resolve(try link.attr("href"), relativeTo: sourceURL), NoticeURL.isArticle(url) {
                    article = (link, url)
                    break
                }
            }
            guard let article else { continue }
            recognizedRows += 1
            guard let date = try publicationDate(in: row), range.allows(date) else {
                filteredCount += 1
                continue
            }
            guard seen.insert(article.url).inserted else { continue }
            let attributeTitle = try article.element.attr("title").trimmingCharacters(in: .whitespacesAndNewlines)
            let ownTitle = article.element.ownText().trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String
            if !attributeTitle.isEmpty {
                title = attributeTitle
            } else if !ownTitle.isEmpty {
                title = ownTitle
            } else if let nested = try article.element.select(".news_title, .title, h3").first() {
                title = try nested.text().trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                title = try article.element.text().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !title.isEmpty else { throw NoticeError.titleNotFound }
            items.append(NoticeSummary(source: source, title: title, url: article.url, publishedDate: date.value))
        }
        guard recognizedRows > 0 else { throw NoticeError.listNotFound }

        let pagination = try document.select(".p_pages").first()
        var previous: URL?
        var next: URL?
        var pageNumbers: [Int] = []
        var currentPage = sourceURL.path == source.listURL.path ? 1 : nil
        if let pagination {
            if let current = try pagination.select(".p_no_d").first(), let number = Int(try current.text()) {
                currentPage = number
            }
            for node in try pagination.select(".p_no, .p_no_d") {
                if let value = Int(try node.text()), value > 0 { pageNumbers.append(value) }
            }
            for link in try pagination.select("a[href]") {
                let title = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = NoticeURL.resolve(try link.attr("href"), relativeTo: sourceURL),
                      NoticeURL.isList(url, source: source), url != sourceURL else { continue }
                if ["上页", "上一页"].contains(title) { previous = url }
                if ["下页", "下一页"].contains(title) { next = url }
            }
        }
        return NoticePage(
            source: source, url: sourceURL, items: items,
            previousPageURL: previous, nextPageURL: next,
            currentPage: currentPage, totalPages: pageNumbers.max(), filteredItemCount: filteredCount
        )
    }

    private func publicationDate(in row: Element) throws -> NoticeDate? {
        if let year = try row.select(".news_date_yy").first(),
           let monthDay = try row.select(".news_date_md").first() {
            return NoticeDate.extract(from: try year.text() + "-" + monthDay.text())
        }
        for element in try row.select("time, .time, .date") {
            let attribute = try element.attr("datetime")
            if !attribute.isEmpty { return NoticeDate.extract(from: attribute) }
            return NoticeDate.extract(from: try element.text())
        }
        for element in try row.select("span") {
            let value = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if value.range(of: #"\A[\[【(]?\s*[0-9]{4}\s*[-年/.]\s*[0-9]{1,2}\s*[-月/.]\s*[0-9]{1,2}日?\s*[\]】)]?\z"#, options: .regularExpression) != nil {
                return NoticeDate.extract(from: value)
            }
        }
        return NoticeDate.extract(from: row.ownText())
    }
}
