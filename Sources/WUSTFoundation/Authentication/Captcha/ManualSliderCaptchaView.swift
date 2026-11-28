#if canImport(SwiftUI) && canImport(WebKit)
import SwiftUI
import Combine
import WebKit

/// Displays the school's real web CAPTCHA; all dragging is handled by its official JavaScript.
@MainActor
public struct ManualSliderCaptchaView: View {
    @StateObject private var model: ManualSliderWebModel
    @State private var finished = false
    private let onVerified: @MainActor () -> Void
    private let onCancel: @MainActor () -> Void

    public init(session: ManualSliderCaptchaSession,
                onVerified: @escaping @MainActor () -> Void,
                onCancel: @escaping @MainActor () -> Void = {}) {
        _model = StateObject(wrappedValue: ManualSliderWebModel(session: session))
        self.onVerified = onVerified
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let webView = model.webView {
                    ManualSliderWebContainer(webView: webView).id(ObjectIdentifier(webView))
                        .opacity(model.phase == .loading ? 0 : 1)
                }
                if model.phase == .idle || model.phase == .loading { ProgressView("正在加载学校验证组件…") }
            }.frame(height: 330)
            Text(model.message).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
            HStack {
                Button("取消") { finished = true; model.cancel(); onCancel() }
                Spacer()
                Button("重新加载") { Task { if await model.load() { finish() } } }
                    .disabled(model.phase == .loading || model.phase == .verifying || model.phase == .verified)
            }.padding(.horizontal, 16)
        }
        .padding(.vertical, 12).frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
        .task {
            guard model.phase == .idle else { return }
            if await model.load() { finish() }
        }
        .onReceive(model.$phase) { if $0 == .verified { finish() } }
        .onDisappear { if !finished { model.cancel() } }
    }
    private func finish() { guard !finished else { return }; finished = true; onVerified() }
}

#if os(macOS)
private struct ManualSliderWebContainer: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
private struct ManualSliderWebContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif

@MainActor
final class ManualSliderWebModel: ObservableObject {
    enum Phase { case idle, loading, ready, verifying, verified, failed, cancelled }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var webView: WKWebView?
    @Published private(set) var message = "由学校网页组件处理拖动与校验"
    private let session: ManualSliderCaptchaSession
    private var configuration: ManualSliderWebConfiguration?
    private var coordinator: OfficialSliderWebCoordinator?
    private var timeout: Task<Void, Never>?

    init(session: ManualSliderCaptchaSession) { self.session = session }
    func load() async -> Bool {
        guard phase != .loading, phase != .verifying, phase != .verified, phase != .cancelled else { return false }
        tearDown()
        phase = .loading
        message = "正在加载学校验证组件…"
        do {
            let value = try await session.webConfiguration()
            guard phase != .cancelled else { return false }
            configuration = value
            if value.alreadyAuthenticated { phase = .verified; return true }
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            config.defaultWebpagePreferences.preferredContentMode = .desktop
            let delegate = OfficialSliderWebCoordinator(owner: self)
            config.userContentController.add(delegate, name: "wustManualCaptcha")
            config.userContentController.addUserScript(WKUserScript(source: OfficialSliderWebPage.script(id: value.id),
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
            for cookie in value.cookies { await config.websiteDataStore.httpCookieStore.setCookie(cookie) }
            guard phase != .cancelled else { return false }
            let view = WKWebView(frame: .zero, configuration: config)
            #if !os(macOS)
            view.scrollView.isScrollEnabled = false
            view.scrollView.bounces = false
            #endif
            view.navigationDelegate = delegate
            view.allowsBackForwardNavigationGestures = false
            coordinator = delegate
            webView = view
            view.loadHTMLString(OfficialSliderWebPage.html, baseURL: OfficialSliderWebPage.componentURL)
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                guard let self, self.phase == .loading else { return }
                self.fail(ManualSliderCaptchaError.webComponentUnavailable)
            }
            return false
        } catch { fail(error); return false }
    }

    func permits(_ request: URLRequest) -> Bool {
        guard configuration != nil, let url = request.url else { return false }
        return (request.httpMethod == "GET" || request.httpMethod == "HEAD") && OfficialSliderWebPage.isComponentURL(url)
    }

    func receive(_ message: WKScriptMessage) {
        guard message.name == "wustManualCaptcha", message.frameInfo.isMainFrame,
              message.webView === webView,
              message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "auth.wust.edu.cn",
              [0, 443].contains(message.frameInfo.securityOrigin.port),
              let config = configuration, let pageURL = webView?.url,
              OfficialSliderWebPage.isComponentURL(pageURL),
              let body = message.body as? [String: Any], body["nonce"] as? String == config.id.uuidString,
              let kind = body["kind"] as? String else { return }
        switch kind {
        case "ready" where phase == .loading:
            timeout?.cancel()
            phase = .ready
            self.message = "请在上方学校组件中手动拖动滑块"
        case "verified" where phase == .ready:
            phase = .verifying
            self.message = "正在接回已验证的登录会话…"
            Task { await accept(config) }
        case "unavailable" where phase == .loading:
            fail(ManualSliderCaptchaError.webComponentUnavailable)
        default: break
        }
    }

    private func accept(_ config: ManualSliderWebConfiguration) async {
        do {
            guard let view = webView else { throw ManualSliderCaptchaError.webComponentUnavailable }
            let cookies = await view.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard phase == .verifying, configuration?.id == config.id, let url = view.url,
                  OfficialSliderWebPage.isComponentURL(url) else { return }
            try await session.acceptWebVerification(id: config.id, pageURL: url, cookies: cookies)
            guard phase != .cancelled else { return }
            phase = .verified
            message = "学校滑块验证已通过"
            tearDown()
        } catch { fail(error) }
    }

    func cancel() { phase = .cancelled; session.cancel(); tearDown() }
    func fail(_ error: any Error) {
        guard phase != .cancelled, phase != .verified else { return }
        timeout?.cancel()
        tearDown()
        if error is CancellationError { phase = .cancelled; message = "验证已取消"; return }
        phase = .failed
        if case ManualSliderCaptchaError.expired = error { message = "验证已过期，请重新加载" }
        else { message = "学校验证组件未能完成加载或会话同步，请重新加载；也可使用官方完整登录页" }
    }
    private func tearDown() {
        timeout?.cancel()
        timeout = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "wustManualCaptcha")
        webView = nil
        coordinator = nil
    }
}

@MainActor
private final class OfficialSliderWebCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var owner: ManualSliderWebModel?
    init(owner: ManualSliderWebModel) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        owner?.permits(action.request) == true && action.targetFrame?.isMainFrame == true ? .allow : .cancel
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        guard webView === owner?.webView, (error as? URLError)?.code != .cancelled else { return }
        owner?.fail(error)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        guard webView === owner?.webView, (error as? URLError)?.code != .cancelled else { return }
        owner?.fail(error)
    }
    // Default WebKit TLS validation is retained; no authentication-challenge override.
}
#endif
