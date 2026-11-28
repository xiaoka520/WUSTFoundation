import Foundation
import Testing
@testable import WUSTFoundation

struct ManualSliderCaptchaTests {
    private func cookies() throws -> [HTTPCookie] {
        [try #require(HTTPCookie(properties: [.domain: "auth.wust.edu.cn", .path: "/authserver/",
            .name: "JSESSIONID", .value: "web-rotated-cookie", .secure: "TRUE"]))]
    }
    private func accept(_ handle: ManualSliderCaptchaSession, _ config: ManualSliderWebConfiguration) async throws {
        try await handle.acceptWebVerification(id: config.id, pageURL: OfficialSliderWebPage.componentURL, cookies: cookies())
    }

    @Test func standaloneComponentRetainsNativeFormAndAdoptsVerifiedCookies() async throws {
        let fixture = try ManualFixture()
        defer { fixture.close() }
        let handle = ManualSliderCaptchaSession(using: fixture.session)
        let config = try await handle.webConfiguration()
        #expect(!config.alreadyAuthenticated)
        #expect(fixture.requests().map(\.httpMethod) == ["GET"])
        let shared = try #require(HTTPCookie(properties: [.domain: ".wust.edu.cn", .path: "/", .name: "shared", .value: "school-synthetic", .secure: "TRUE"]))
        let foreign = try #require(HTTPCookie(properties: [.domain: "other.invalid", .path: "/", .name: "foreign", .value: "foreign-synthetic"]))
        try await handle.acceptWebVerification(id: config.id, pageURL: OfficialSliderWebPage.componentURL, cookies: cookies() + [shared, foreign])
        let stored = fixture.session.configuration.httpCookieStorage?.cookies(for: config.loginURL) ?? []
        #expect(stored.contains { $0.name == "JSESSIONID" && $0.value == "web-rotated-cookie" })
        #expect(stored.contains { $0.name == "shared" && $0.value == "school-synthetic" })
        #expect(!(fixture.session.configuration.httpCookieStorage?.cookies ?? []).contains { $0.name == "foreign" })
        _ = try await handle.complete(username: "synthetic-account", password: "synthetic-password")
        let requests = fixture.requests()
        #expect(requests.map { "\($0.httpMethod!) \($0.url!.lastPathComponent)" } == ["GET login", "POST login", "GET jsxsd"])
        let body = String(decoding: try #require(requests[1].httpBody), as: UTF8.self)
        #expect(body.contains("execution=manual-form-1"))
        #expect(!body.contains("synthetic-password"))
        await #expect(throws: CancellationError.self) { _ = try await handle.complete(username: "x", password: "x") }
    }

    @Test func cannotSubmitPasswordBeforeWebVerificationAndOldPagesCannotBeReplayed() async throws {
        let fixture = try ManualFixture()
        defer { fixture.close() }
        let handle = ManualSliderCaptchaSession(using: fixture.session)
        let old = try await handle.webConfiguration()
        await #expect(throws: ManualSliderCaptchaError.verificationRequired) { _ = try await handle.complete(username: "x", password: "x") }
        let current = try await handle.webConfiguration()
        await #expect(throws: ManualSliderCaptchaError.verificationRequired) { try await accept(handle, old) }
        try await accept(handle, current)
        await #expect(throws: ManualSliderCaptchaError.verificationRequired) { try await accept(handle, current) }
        #expect(fixture.requests().map(\.httpMethod) == ["GET", "GET"])
        handle.cancel()
    }

    @Test func rejectsForeignPagesAndMissingCookies() async throws {
        let fixture = try ManualFixture()
        defer { fixture.close() }
        let handle = ManualSliderCaptchaSession(using: fixture.session)
        let config = try await handle.webConfiguration()
        await #expect(throws: AuthServerLoginError.invalidResponse) {
            try await handle.acceptWebVerification(id: config.id, pageURL: URL(string: "https://evil.invalid/authserver/login")!, cookies: cookies())
        }
        await #expect(throws: AuthServerLoginError.invalidResponse) {
            try await handle.acceptWebVerification(id: config.id, pageURL: OfficialSliderWebPage.componentURL, cookies: [])
        }
        #expect(fixture.requests().count == 1)
        handle.cancel()
    }

    @Test func localExpiryPreventsStalePagesAndStalePasswordContinuation() async throws {
        let fixture = try ManualFixture()
        defer { fixture.close() }
        let clock = ManualFixtureClock()
        let handle = ManualSliderCaptchaSession(using: fixture.session, now: { clock.read() })
        let old = try await handle.webConfiguration()
        clock.advance(121)
        await #expect(throws: ManualSliderCaptchaError.expired) { try await accept(handle, old) }
        let next = try await handle.webConfiguration()
        try await accept(handle, next)
        clock.advance(121)
        await #expect(throws: ManualSliderCaptchaError.expired) { _ = try await handle.complete(username: "x", password: "x") }
        #expect(fixture.requests().count == 2)
        handle.cancel()
    }

    @Test func clientBindsWebSessionsAndCancelsThemOnReplacementAndLogout() async throws {
        let fixture = try ManualFixture()
        defer { fixture.close() }
        let client = try WUSTLoginClient(username: "test", sessionConfiguration: fixture.configuration)
        let old = try await client.prepareManualAuthServerLogin()
        let next = try await client.prepareManualAuthServerLogin()
        await #expect(throws: CancellationError.self) { _ = try await old.webConfiguration() }
        await #expect(throws: WUSTLoginClientError.verificationNotPending) { _ = try await client.loginWithManualAuthServer(password: "x", verification: old) }
        _ = try await next.webConfiguration()
        try await client.logout()
        await #expect(throws: CancellationError.self) { _ = try await next.webConfiguration() }
        #expect(fixture.requests().count == 1)
    }

    @Test @MainActor func cancellingCallerStopsPasswordSubmission() async throws {
        let fixture = try ManualFixture()
        defer { fixture.close() }
        let client = try WUSTLoginClient(username: "test", sessionConfiguration: fixture.configuration)
        let handle = try await client.prepareManualAuthServerLogin()
        try await accept(handle, handle.webConfiguration())
        let task = Task { try await client.loginWithManualAuthServer(password: "x", verification: handle) }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(fixture.requests().count == 1)
    }

    @Test func badPasswordPropagatesAsTheDistinctCredentialError() async throws {
        let fixture = try ManualFixture(passwordError: "用户名或密码错误")
        defer { fixture.close() }
        let handle = ManualSliderCaptchaSession(using: fixture.session)
        try await accept(handle, handle.webConfiguration())
        await #expect(throws: AuthServerCredentialError.invalidCredentials) {
            _ = try await handle.complete(username: "synthetic-account", password: "synthetic-password")
        }
        #expect(fixture.requests().map(\.httpMethod) == ["GET", "POST"])
    }
}

private final class ManualFixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date()
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); date.addTimeInterval(seconds); lock.unlock() }
}

private struct ManualFixture {
    let id = UUID().uuidString
    let configuration: URLSessionConfiguration
    let session: URLSession
    init(codes: [Int] = [1], passwordError: String? = nil) throws {
        let challenge = try SliderCaptchaTests.challenge()
        let json = try JSONSerialization.data(withJSONObject: ["bigImage": challenge.bigImage,
            "smallImage": challenge.smallImage, "tagWidth": challenge.tagWidth, "yHeight": challenge.yHeight])
        configuration = .ephemeral
        configuration.protocolClasses = [ManualProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Manual-Test": id]
        session = URLSession(configuration: configuration)
        ManualProtocol.register(id, image: json, codes: codes, passwordError: passwordError)
    }
    func requests() -> [URLRequest] { ManualProtocol.requests(id) }
    func close() { session.invalidateAndCancel(); ManualProtocol.remove(id) }
}

private final class ManualProtocol: URLProtocol, @unchecked Sendable {
    private struct State { let image: Data; let codes: [Int]; let passwordError: String?; var requests: [URLRequest] = []; var forms = 0; var verified = 0 }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var states: [String: State] = [:]
    static func register(_ id: String, image: Data, codes: [Int], passwordError: String?) { lock.lock(); defer { lock.unlock() }; states[id] = State(image: image, codes: codes, passwordError: passwordError) }
    static func requests(_ id: String) -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return states[id]?.requests ?? [] }
    static func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; states[id] = nil }
    override class func canInit(with request: URLRequest) -> Bool { request.value(forHTTPHeaderField: "X-Manual-Test") != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open(); defer { stream.close() }
            var body = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count == 0 { break }
                guard count > 0 else { client?.urlProtocol(self, didFailWithError: URLError(.cannotDecodeRawData)); return }
                body.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = body
        }
        guard let reply = Self.reply(captured) else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        if reply.0.statusCode == 302, let location = reply.0.value(forHTTPHeaderField: "Location"), let url = URL(string: location) {
            var next = URLRequest(url: url)
            next.httpMethod = "GET"
            next.setValue(captured.value(forHTTPHeaderField: "X-Manual-Test"), forHTTPHeaderField: "X-Manual-Test")
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: reply.0)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: reply.0, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    private static func reply(_ request: URLRequest) -> (HTTPURLResponse, Data)? {
        lock.lock(); defer { lock.unlock() }
        guard let id = request.value(forHTTPHeaderField: "X-Manual-Test"), var state = states[id], let url = request.url else { return nil }
        state.requests.append(request)
        let responseURL = url
        var headers: [String: String] = [:]
        var status = 200
        let data: Data
        switch url.lastPathComponent {
        case "login" where request.httpMethod == "GET":
            state.forms += 1
            data = Data("""
            <form id="pwdFromId" action="/authserver/login" method="post">
            <input id="pwdEncryptSalt" type="hidden" value="0123456789abcdef">
            <input name="execution" type="hidden" value="manual-form-\(state.forms)">
            <input name="_eventId" type="hidden" value="submit"></form>
            """.utf8)
        case "openSliderCaptcha.htl": data = state.image
        case "verifySliderCaptcha.htl":
            let code = state.codes[min(state.verified, state.codes.count - 1)]
            state.verified += 1
            data = Data("{\"errorCode\":\(code)}".utf8)
        case "login":
            if let message = state.passwordError {
                data = Data("<form id='pwdFromId'><span id='showErrorTip'>\(message)</span></form>".utf8)
            } else {
                status = 302
                headers["Location"] = "https://bkjx.wust.edu.cn/jsxsd/"
                data = Data()
            }
        case "jsxsd":
            headers["Set-Cookie"] = "JSESSIONID=manual-synthetic; Path=/jsxsd/; Secure; HttpOnly"
            data = Data()
        case "blankPage.jsp": data = Data()
        case "xsxx":
            var rows = Array(repeating: ["", "姓名示例", "", "性别示例"], count: 50)
            rows[2] = ["院系：示例院系", "专业：示例专业", "", "班级：示例班级", "学号：synthetic-account"]
            let table = "<table id='xjkpTable'><tbody>" + rows.map { "<tr>" + $0.map { "<td>" + $0 + "</td>" }.joined() + "</tr>" }.joined() + "</tbody></table>"
            data = Data(table.utf8)
        default: return nil
        }
        states[id] = state
        return (HTTPURLResponse(url: responseURL, statusCode: status, httpVersion: nil, headerFields: headers)!, data)
    }
}
