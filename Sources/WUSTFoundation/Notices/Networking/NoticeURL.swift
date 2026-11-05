import Foundation

enum NoticeURL {
    static func resolve(_ value: String, relativeTo base: URL) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let url = URL(string: value, relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func isUniversityURL(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(),
              url.port == nil || url.port == 80 || url.port == 443 else { return false }
        return host == "wust.edu.cn" || host.hasSuffix(".wust.edu.cn")
    }

    static func isList(_ url: URL, source: NoticeSource) -> Bool {
        guard isUniversityURL(url), url.host?.lowercased() == source.listURL.host,
              url.query == nil else { return false }
        let path = source.listURL.path
        if url.path == path { return true }
        let prefix = String(path.dropLast(4)) + "/"
        guard url.path.hasPrefix(prefix) else { return false }
        return String(url.path.dropFirst(prefix.count)).range(of: #"\A[0-9]+\.htm\z"#, options: .regularExpression) != nil
    }

    static func isArticle(_ url: URL) -> Bool {
        if url.path.range(of: #"/info/[0-9]+/[0-9]+\.htm\z"#, options: .regularExpression) != nil { return true }
        guard url.path.hasSuffix("/info.jsp"),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        return items.contains { $0.name == "urltype" && $0.value == "news.NewsContentUrl" }
    }
}
