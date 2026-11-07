#if canImport(WebKit)
import Foundation
import WebKit

@MainActor
public enum LaundryWebLogin {
    public static let url = URL(string: "https://h5.qiekj.com/login")!

    public static func credential(from webView: WKWebView, using service: LaundryAuthService = .init()) async throws -> LaundryCredential {
        guard webView.url?.scheme == "https", webView.url?.host == url.host,
              webView.url?.port == nil || webView.url?.port == 443 else {
            throw LaundryAuthError.unexpectedWebOrigin
        }

        let result = try await webView.evaluateJavaScript("""
        window.location.origin === "https://h5.qiekj.com" ? localStorage.getItem("token") : null
        """)
        guard let token = result as? String, !token.isEmpty else { throw LaundryAuthError.loginRequired }
        return try await service.validate(token: token)
    }
}
#endif
