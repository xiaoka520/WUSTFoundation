import Foundation
import Testing
@testable import WUSTFoundation

@Suite(.serialized)
struct AuthServerSMSLoginTests {
    static let form = """
    <form id="phoneFromId" action="/authserver/login" method="post">
      <input type="hidden" name="execution" value="e1s1">
      <input type="hidden" name="_eventId" value="submit">
      <input type="hidden" name="cllt" value="dynamicLogin">
      <input type="hidden" name="dllt" value="generalLogin">
    </form>
    """

    @Test func sentCodeRetainsTheFormAndRejectedCodeRefreshesExecution() async throws {
        SMSProtocol.reset()
        let session = session()
        defer { session.invalidateAndCancel() }
        let service = AuthServerSMSLoginService()
        let context = try await service.sendCode(account: "fixture-account", using: session)
        #expect(context.resendAfterSeconds == 120)
        #expect(context.description == "AuthServerSMSLoginContext")
        let result = try await service.login(code: "012345", context: context, using: session)
        guard case .loginNotCompleted(let refreshed) = result else {
            Issue.record("A login form response was accepted as authenticated")
            return
        }
        #expect(refreshed.fields["execution"] == "e1s2")
        let request = try AuthServerSMSLoginService.submission(code: "123456", context: refreshed)
        let fields = try SMSProtocol.fields(request)
        #expect(fields["execution"] == "e1s2")
        #expect(fields["cllt"] == "dynamicLogin")
        #expect(fields["dynamicCode"] == "123456")
        #expect(fields["password"] == nil)
        #expect(request.url == context.loginURL)
        #expect(SMSProtocol.smsCalls == 1)
    }

    @Test func sliderRejectionPreventsTheSMSRequest() async throws {
        SMSProtocol.reset(sliderCode: 0)
        let session = session()
        defer { session.invalidateAndCancel() }
        await #expect(throws: SliderCaptchaError.rejected(0)) {
            try await AuthServerSMSLoginService().sendCode(account: "fixture-account", using: session, maxSliderAttempts: 1)
        }
        #expect(SMSProtocol.smsCalls == 0)
    }

    @Test func HTTP200WithRejectedSMSCodeIsNotAccepted() async throws {
        SMSProtocol.reset(responseCode: "timeExpire")
        let session = session()
        defer { session.invalidateAndCancel() }
        await #expect(throws: AuthServerLoginError.smsCodeRejected("timeExpire")) {
            try await AuthServerSMSLoginService().sendCode(account: "fixture-account", using: session)
        }
        #expect(SMSProtocol.smsCalls == 1)
    }

    @Test func missingExecutionAndForeignActionsAreRejected() throws {
        let loginURL = URL(string: "https://auth.wust.edu.cn/authserver/login")!
        let invalidForms = [Self.form.replacingOccurrences(of: "name=\"execution\"", with: "name=\"other\""),
                            Self.form.replacingOccurrences(of: "/authserver/login\"", with: "https://other.invalid/authserver/login\"")]
        for html in invalidForms {
            #expect(throws: AuthServerLoginError.invalidForm) {
                try AuthServerSMSLoginService.formFields(html: html, loginURL: loginURL, account: "fixture")
            }
        }
    }

    @Test func clientRetainsRetryStateAndLogoutClearsIt() async throws {
        SMSProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SMSProtocol.self]
        let client = try WUSTLoginClient(username: "fixture-account", deviceID: "fixture-device", sessionConfiguration: config)
        await #expect(throws: WUSTLoginClientError.verificationNotPending) {
            try await client.loginWithSMSCode("123456")
        }
        #expect(try await client.sendLoginSMSCode(to: "fixture-account") == 120)
        for _ in 0..<2 {
            await #expect(throws: AuthServerLoginError.loginNotCompleted) {
                try await client.loginWithSMSCode("123456")
            }
        }
        #expect(SMSProtocol.smsCalls == 1)
        try await client.logout()
        await #expect(throws: WUSTLoginClientError.verificationNotPending) {
            try await client.loginWithSMSCode("123456")
        }
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SMSProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class SMSProtocol: URLProtocol, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var calls = 0
        var sliderCode = 1
        var responseCode = "success"
    }
    private static let state = State()
    static var smsCalls: Int {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.calls
    }
    static func reset(sliderCode: Int = 1, responseCode: String = "success") {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.calls = 0
        state.sliderCode = sliderCode
        state.responseCode = responseCode
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let url = try #require(request.url)
            let data: Data
            switch url.path {
            case "/authserver/login":
                let form = request.httpMethod == "POST"
                    ? AuthServerSMSLoginTests.form.replacingOccurrences(of: "e1s1", with: "e1s2")
                    : AuthServerSMSLoginTests.form
                data = Data(form.utf8)
            case "/authserver/common/openSliderCaptcha.htl":
                let challenge = try SliderCaptchaTests.challenge()
                data = try JSONSerialization.data(withJSONObject: ["bigImage": challenge.bigImage,
                    "smallImage": challenge.smallImage, "tagWidth": challenge.tagWidth, "yHeight": challenge.yHeight])
            case "/authserver/common/verifySliderCaptcha.htl":
                Self.state.lock.lock()
                let code = Self.state.sliderCode
                Self.state.lock.unlock()
                data = Data("{\"errorCode\":\(code)}".utf8)
            case "/authserver/dynamicCode/getDynamicCode.htl":
                let fields = try Self.fields(request)
                let encrypted = try #require(fields["mobile"])
                #expect(Data(base64Encoded: encrypted) != nil)
                #expect(encrypted != "fixture-account")
                #expect(fields["captcha"] == "")
                #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
                Self.state.lock.lock()
                Self.state.calls += 1
                let code = Self.state.responseCode
                Self.state.lock.unlock()
                data = try JSONSerialization.data(withJSONObject: ["code": code, "intervalTime": "120"])
            default:
                throw URLError(.unsupportedURL)
            }
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    static func fields(_ request: URLRequest) throws -> [String: String] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream, request.httpBody == nil {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        var components = URLComponents()
        components.percentEncodedQuery = String(decoding: data, as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}
