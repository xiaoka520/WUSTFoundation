import Foundation
import CoreFoundation

public struct NoticeService: Sendable {
    private let datePolicy: NoticeDatePolicy
    private let maximumPDFBytes: Int

    public init(
        datePolicy: NoticeDatePolicy = NoticeDatePolicy(),
        maximumPDFBytes: Int = 20 * 1024 * 1024
    ) {
        self.datePolicy = datePolicy
        self.maximumPDFBytes = maximumPDFBytes
    }

    public func fetchPage(
        source: NoticeSource,
        at pageURL: URL? = nil,
        using session: URLSession
    ) async throws -> NoticePage {
        let url = pageURL ?? source.listURL
        guard NoticeURL.isList(url, source: source) else { throw NoticeError.unsupportedURL }
        _ = try datePolicy.resolve()
        let page = try await fetchHTML(url, using: session)
        guard NoticeURL.isList(page.url, source: source) else { throw NoticeError.unexpectedRedirect }
        return try NoticeListParser().parse(
            from: page.html, source: source, sourceURL: page.url,
            datePolicy: datePolicy
        )
    }

    public func fetchDetail(_ summary: NoticeSummary, using session: URLSession) async throws -> NoticeDetail {
        guard NoticeURL.isUniversityURL(summary.url), NoticeURL.isArticle(summary.url) else {
            throw NoticeError.unsupportedURL
        }
        let range = try datePolicy.resolve()
        guard let date = NoticeDate.parseExact(summary.publishedDate) else { throw NoticeError.missingPublicationDate }
        guard range.allows(date) else { throw NoticeError.filteredPublicationDate }
        let page = try await fetchHTML(summary.url, using: session)
        guard NoticeURL.isArticle(page.url) else { throw NoticeError.unexpectedRedirect }
        return try NoticeDetailParser().parse(
            from: page.html, summary: summary, responseURL: page.url,
            datePolicy: datePolicy
        )
    }

    private func fetchHTML(_ url: URL, using session: URLSession) async throws -> (html: String, url: URL) {
        guard NoticeURL.isUniversityURL(url) else { throw NoticeError.unsupportedURL }
        let request = makeRequest(url)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, let finalURL = response.url else { throw NoticeError.invalidResponse }
        if response.statusCode == 401 || ["auth.wust.edu.cn", "atrust.wust.edu.cn"].contains(finalURL.host ?? "") {
            throw NoticeError.authenticationRequired
        }
        guard response.statusCode == 200 else { throw NoticeError.unexpectedStatusCode(response.statusCode) }
        guard NoticeURL.isUniversityURL(finalURL) else { throw NoticeError.unexpectedRedirect }
        if let html = String(data: data, encoding: .utf8) { return (html, finalURL) }
        let charset = response.textEncodingName?.lowercased() ?? ""
        if ["gbk", "gb2312", "gb18030"].contains(charset) {
            let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            if let html = String(data: data, encoding: String.Encoding(rawValue: raw)) { return (html, finalURL) }
        }
        throw NoticeError.invalidEncoding
    }

    public func fetchPDF(_ document: NoticeDocument, using session: URLSession) async throws -> Data {
        guard maximumPDFBytes > 0 else { throw NoticeError.invalidConfiguration }
        guard NoticeURL.isUniversityURL(document.url), document.url.pathExtension.lowercased() == "pdf",
              NoticeURL.isUniversityURL(document.sourceURL), NoticeURL.isArticle(document.sourceURL) else {
            throw NoticeError.unsupportedURL
        }
        var request = makeRequest(document.url)
        request.setValue(document.sourceURL.absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, let finalURL = response.url else {
            throw NoticeError.invalidResponse
        }
        if response.statusCode == 401 || ["auth.wust.edu.cn", "atrust.wust.edu.cn"].contains(finalURL.host ?? "") {
            throw NoticeError.authenticationRequired
        }
        guard response.statusCode == 200 else { throw NoticeError.unexpectedStatusCode(response.statusCode) }
        guard NoticeURL.isUniversityURL(finalURL) else { throw NoticeError.unexpectedRedirect }
        guard data.count <= maximumPDFBytes else { throw NoticeError.documentTooLarge }
        guard data.starts(with: Data("%PDF-".utf8)) else { throw NoticeError.invalidDocument }
        return data
    }

    private func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        return request
    }
}
