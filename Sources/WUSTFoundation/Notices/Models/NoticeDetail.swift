import Foundation

public struct NoticeLink: Codable, Hashable, Sendable {
    public let title: String
    public let url: URL
}

public struct NoticeImage: Codable, Hashable, Sendable {
    public let url: URL
    public let alt: String?
}

public struct NoticeDocument: Codable, Hashable, Sendable {
    public let url: URL
    public let sourceURL: URL
}

public struct NoticeDetail: Codable, Hashable, Sendable {
    public let summary: NoticeSummary
    public let text: String
    public let paragraphs: [String]
    public let images: [NoticeImage]
    public let attachments: [NoticeLink]
    public let links: [NoticeLink]
    public let documents: [NoticeDocument]

    public var hasText: Bool { !text.isEmpty }
}
