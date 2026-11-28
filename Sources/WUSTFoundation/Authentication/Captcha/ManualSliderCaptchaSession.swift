import Foundation

public enum ManualSliderCaptchaError: Error, Sendable, Equatable {
    case operationInProgress
    case verificationRequired
    case expired
    case invalidGesture
    case invalidImage
    case webComponentUnavailable
}

/// Password-login session bound to a user-operated official web CAPTCHA.
public actor ManualSliderCaptchaSession: Identifiable {
    public nonisolated let id = UUID()
    private let transport: URLSession
    private nonisolated let lifetime: ManualCaptchaLifetime
    private let now: @Sendable () -> Date
    private var busy = false
    private var consumed = false
    private var preparation: ManualAuthServerLoginPreparation?
    private var pendingWeb: (id: UUID, created: Date)?
    private var verifiedAt: Date?

    init(using session: URLSession, now: @escaping @Sendable () -> Date = { Date() }) {
        transport = session
        lifetime = ManualCaptchaLifetime(session: session)
        self.now = now
    }
    deinit { lifetime.cancel() }
    public nonisolated func cancel() { lifetime.cancel() }

    func webConfiguration() async throws -> ManualSliderWebConfiguration {
        try checkActive()
        guard !busy else { throw ManualSliderCaptchaError.operationInProgress }
        busy = true
        defer { busy = false }
        pendingWeb = nil
        preparation = nil
        verifiedAt = nil
        let form = try await AuthServerLoginService().prepareManualLogin(using: transport)
        try checkActive()
        preparation = form
        let id = UUID()
        if form.html == nil { verifiedAt = now() }
        else { pendingWeb = (id, now()) }
        return ManualSliderWebConfiguration(id: id, loginURL: form.loginURL,
            cookies: transport.configuration.httpCookieStorage?.cookies ?? [], alreadyAuthenticated: form.html == nil)
    }

    /// Used only by the private WKWebView bridge after observing an actual successful server response.
    func acceptWebVerification(id: UUID, pageURL: URL, cookies: [HTTPCookie]) throws {
        try checkActive()
        guard !busy else { throw ManualSliderCaptchaError.operationInProgress }
        guard let pendingWeb, pendingWeb.id == id, let original = preparation else {
            throw ManualSliderCaptchaError.verificationRequired
        }
        try checkFresh(pendingWeb.created)
        guard OfficialSliderWebPage.isComponentURL(pageURL) else {
            throw AuthServerLoginError.invalidResponse
        }
        let host = original.loginURL.host ?? ""
        let authCookies = cookies.filter { Self.isLoginCookie($0, host: host) }
        guard !authCookies.isEmpty, let storage = transport.configuration.httpCookieStorage else {
            throw AuthServerLoginError.invalidResponse
        }
        // Only CAPTCHA requests run in WebKit. Keep the original native login form/execution;
        // no second login-page GET is allowed to rotate that form underneath this session.
        for cookie in storage.cookies ?? [] where Self.isLoginCookie(cookie, host: host) {
            storage.deleteCookie(cookie)
        }
        storage.setCookies(authCookies, for: original.loginURL, mainDocumentURL: original.loginURL)
        self.pendingWeb = nil
        verifiedAt = now()
    }

    func complete(username: String, password: String) async throws -> [HTTPCookie] {
        try checkActive()
        guard !busy else { throw ManualSliderCaptchaError.operationInProgress }
        guard let verifiedAt, let preparation else { throw ManualSliderCaptchaError.verificationRequired }
        guard !password.isEmpty else { throw AuthServerLoginError.invalidInput }
        try checkFresh(verifiedAt)
        consumed = true
        defer { lifetime.cancel() }
        try await AuthServerLoginService().submitManuallyVerifiedLogin(username: username, password: password,
            preparation: preparation, using: transport)
        try Task.checkCancellation()
        guard !lifetime.isCancelled else { throw CancellationError() }
        return transport.configuration.httpCookieStorage?.cookies ?? []
    }

    private func checkActive() throws {
        try Task.checkCancellation()
        guard !lifetime.isCancelled else { throw CancellationError() }
        guard !consumed else { throw ManualSliderCaptchaError.verificationRequired }
    }
    private nonisolated static func isLoginCookie(_ cookie: HTTPCookie, host: String) -> Bool {
        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return domain == host || (cookie.domain.hasPrefix(".") && domain == "wust.edu.cn" && host.hasSuffix(".wust.edu.cn"))
    }
    private func checkFresh(_ date: Date) throws {
        let age = now().timeIntervalSince(date)
        guard age >= 0, age < 120 else { throw ManualSliderCaptchaError.expired }
    }
}

struct ManualSliderWebConfiguration: Sendable {
    let id: UUID
    let loginURL: URL
    let cookies: [HTTPCookie]
    let alreadyAuthenticated: Bool
}

private final class ManualCaptchaLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let session: URLSession
    init(session: URLSession) { self.session = session }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() {
        lock.lock()
        let shouldCancel = !cancelled
        cancelled = true
        lock.unlock()
        if shouldCancel { session.invalidateAndCancel() }
    }
}

struct ManualAuthServerLoginPreparation: Sendable {
    let loginURL: URL
    let service: URL
    let html: String?
}
