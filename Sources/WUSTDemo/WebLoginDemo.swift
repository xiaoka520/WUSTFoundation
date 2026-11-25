#if os(macOS)
import AppKit
import WebKit
import WUSTFoundation

@MainActor
final class WebLoginDemo: NSObject, NSWindowDelegate {
    private let client: WUSTLoginClient
    private let smsLogin: Bool
    private let webView = UndergraduateWebLogin.makeWebView()
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
    )
    private let status = NSTextField(labelWithString: "选择「账号登录」，使用学号和密码完成学校要求的验证。")
    private lazy var confirmButton = NSButton(title: "检查教务登录", target: self, action: #selector(checkLogin))
    private var continuation: CheckedContinuation<WUSTLoginResult, Error>?

    private init(client: WUSTLoginClient, smsLogin: Bool) {
        self.client = client
        self.smsLogin = smsLogin
    }

    static func run(using client: WUSTLoginClient, smsLogin: Bool = false) async throws -> WUSTLoginResult {
        let demo = WebLoginDemo(client: client, smsLogin: smsLogin)
        return try await demo.present()
    }

    private func present() async throws -> WUSTLoginResult {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        window.title = "武汉科技大学 · 教务登录"
        window.isReleasedWhenClosed = false
        window.delegate = self
        if smsLogin { status.stringValue = "选择「短信登录」，使用当前学号绑定的手机号完成登录，再检查教务登录。" }

        let content = NSView()
        let toolbar = NSStackView(views: [status, confirmButton])
        toolbar.spacing = 12
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(toolbar)
        content.addSubview(webView)
        window.contentView = content
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            var components = URLComponents(url: UndergraduateWebLogin.url, resolvingAgainstBaseURL: false)!
            if smsLogin {
                components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "type", value: "dynamicLogin")]
            }
            webView.load(URLRequest(url: components.url!))
            window.center()
            window.makeKeyAndOrderFront(nil)
            app.activate()
        }
    }

    @objc private func checkLogin() {
        confirmButton.isEnabled = false
        status.stringValue = "正在核对教务会话和学号……"
        Task {
            do {
                let result = try await UndergraduateWebLogin.complete(in: webView, using: client)
                let pending = continuation
                continuation = nil
                window.close()
                pending?.resume(returning: result)
            } catch WUSTLoginClientError.studentIDMismatch {
                status.stringValue = "网页学号与终端输入不一致。请关闭窗口后重新登录。"
                confirmButton.isEnabled = true
            } catch WUSTLoginClientError.notAuthenticated {
                status.stringValue = "请在学校页面完成登录，进入教务系统后再检查。"
                confirmButton.isEnabled = true
            } catch {
                status.stringValue = "教务会话校验失败（\(type(of: error))），可重新检查。"
                confirmButton.isEnabled = true
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmButton.isEnabled
    }

    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        let pending = continuation
        continuation = nil
        pending?.resume(throwing: CancellationError())
    }
}
#endif
