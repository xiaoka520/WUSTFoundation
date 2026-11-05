import Foundation

public struct NoticeSummary: Codable, Hashable, Sendable {
    public let source: NoticeSource
    public let title: String
    public let url: URL
    public let publishedDate: String

    public init(source: NoticeSource, title: String, url: URL, publishedDate: String) {
        self.source = source
        self.title = title
        self.url = url
        self.publishedDate = publishedDate
    }
}

public struct NoticePage: Codable, Hashable, Sendable {
    public let source: NoticeSource
    public let url: URL
    public let items: [NoticeSummary]
    public let previousPageURL: URL?
    public let nextPageURL: URL?
    public let currentPage: Int?
    public let totalPages: Int?
    public let filteredItemCount: Int
}
