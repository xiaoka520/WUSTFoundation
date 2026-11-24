#if canImport(WebKit)
import Foundation
import WebKit

@MainActor
public enum UndergraduateWebLogin {
    public static let url = URL(string: "https://auth.wust.edu.cn/authserver/login?service=https%3A%2F%2Fbkjx.wust.edu.cn%2Fjsxsd%2F")!

    public static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: configuration)
    }

    public static func complete(in webView: WKWebView, using client: WUSTLoginClient) async throws -> WUSTLoginResult {
        guard isUndergraduatePage(webView.url) else {
            throw WUSTLoginClientError.notAuthenticated
        }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard isUndergraduatePage(webView.url) else {
            throw WUSTLoginClientError.notAuthenticated
        }
        return try await client.adoptUndergraduateWebSession(cookies)
    }

    private static func isUndergraduatePage(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.host == "bkjx.wust.edu.cn",
              url.port == nil || url.port == 443 else { return false }
        return url.path == "/jsxsd" || url.path.hasPrefix("/jsxsd/")
    }
}
#endif
