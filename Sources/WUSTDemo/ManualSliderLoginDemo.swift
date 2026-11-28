#if os(macOS)
import AppKit
import SwiftUI
import WUSTFoundation

@MainActor
final class ManualSliderLoginDemo: NSObject, NSWindowDelegate {
    private let verification: ManualSliderCaptchaSession
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private var continuation: CheckedContinuation<Void, Error>?

    private init(verification: ManualSliderCaptchaSession) { self.verification = verification }

    /// Anonymous UI preview: no account/password is loaded or submitted.
    static func preview() async throws {
        let client = try WUSTLoginClient(username: "manual-preview")
        let verification = try await client.prepareManualAuthServerLogin()
        defer { verification.cancel() }
        try await ManualSliderLoginDemo(verification: verification).present()
    }

    static func run(using client: WUSTLoginClient, password: String) async throws -> WUSTLoginResult {
        let verification = try await client.prepareManualAuthServerLogin()
        do {
            try await ManualSliderLoginDemo(verification: verification).present()
            return try await client.loginWithManualAuthServer(password: password, verification: verification)
        } catch {
            verification.cancel()
            await client.cancelManualAuthServerLogin()
            throw error
        }
    }

    private func present() async throws {
        NSApplication.shared.setActivationPolicy(.regular)
        window.title = "武汉科技大学 · 手动滑动验证"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ManualSliderCaptchaView(session: verification,
            onVerified: { [weak self] in self?.finish() }, onCancel: { [weak self] in self?.cancel() }))
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
        }
    }

    private func finish() {
        let pending = continuation
        continuation = nil
        window.close()
        pending?.resume()
    }

    private func cancel() {
        verification.cancel()
        let pending = continuation
        continuation = nil
        window.close()
        pending?.resume(throwing: CancellationError())
    }

    func windowWillClose(_ notification: Notification) { if continuation != nil { cancel() } }
}
#endif
