import Foundation
import Testing
@testable import WUSTFoundation

final class LoginTestServer: @unchecked Sendable {
    static let shared = LoginTestServer()
    private let lock = NSLock()
    var scenario = Scenario()
    struct Scenario {
        var counts: [String: Int] = [:]
        var expired = false
        var offline = false
        var needSMS = false
        var smsVerified = false
        var smsFailure = false
        var nextService = ""
        var blankPageBody = ""
        var blankPageRedirect = false
        var reportFailure = false
        var delay: TimeInterval = 0
        var studentID = "test-account"
        var expireOnMint: Int? = nil
        var requests: [URLRequest] = []
    }
    func reset() { lock.lock(); defer { lock.unlock() }; scenario = Scenario() }
    func update(_ body: (inout Scenario) -> Void) { lock.lock(); defer { lock.unlock() }; body(&scenario) }
    func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return scenario.counts[path, default: 0] }
    func requests() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return scenario.requests }

    func response(_ request: URLRequest) throws -> (HTTPURLResponse, Data, TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        let url = request.url!
        let path = url.path
        scenario.counts[path, default: 0] += 1
        scenario.requests.append(request)
        if scenario.offline { throw URLError(.notConnectedToInternet) }
        let delay = scenario.delay
        var finalURL = url
        var headers: [String: String] = [:]
        var status = 200
        var text: String
        let service = "https://atrust.wust.edu.cn/passport/v1/auth/cas?sfDomain=test"
        switch (url.host, path) {
        case ("atrust.wust.edu.cn", "/passport/v1/public/authConfig"):
            text = #"{"code":0,"data":{"authServerInfoList":[{"authType":"auth/cas","loginUrl":"/test-cas-entry"}],"security":{"csrfToken":"test-csrf"}}}"#
        case ("atrust.wust.edu.cn", "/test-cas-entry"):
            var parts = URLComponents(string: "https://auth.wust.edu.cn/lyuapServer/login")!
            parts.queryItems = [URLQueryItem(name: "service", value: service)]
            finalURL = parts.url!
            text = "login"
        case ("auth.wust.edu.cn", "/lyuapServer/kaptcha"):
            text = #"{"uid":"test-captcha","content":"data:image/png;base64,dGVzdA=="}"#
        case ("auth.wust.edu.cn", "/lyuapServer/loginType"):
            text = #"{"meta":{"success":true,"statusCode":200},"data":{"isVerifyCode":"1","captchaType":"1","isTwoVerify":"1","twoVerifyWay":"1"}}"#
        case ("auth.wust.edu.cn", "/lyuapServer/v1/tickets"):
            if scenario.needSMS && !scenario.smsVerified {
                let details = #"{"phone":"test-phone","twoVerifyType":"test-policy"}"#
                let object: [String: Any] = ["data": ["code": "TWOVERIFY", "uid": "test-challenge", "data": details]]
                text = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            } else { text = #"{"tgt":"TGT-test"}"# }
        case ("auth.wust.edu.cn", "/lyuapServer/login/mobile/generateCode"):
            if scenario.smsFailure { text = #"{"meta":{"success":false,"statusCode":500,"message":"synthetic rejection"},"data":false}"# }
            else { text = #"{"meta":{"success":true,"statusCode":200},"data":true}"# }
        case ("auth.wust.edu.cn", "/lyuapServer/login/twoVertify"):
            scenario.smsVerified = true
            text = #"{"meta":{"success":true,"statusCode":200},"data":{"flag":true}}"#
        case ("auth.wust.edu.cn", "/lyuapServer/v1/tickets/TGT-test"):
            if scenario.expired || scenario.expireOnMint == scenario.counts[path] { status = 500; text = "TGT :synthetic credential expired" }
            else { text = "ST-test" }
        case ("atrust.wust.edu.cn", "/passport/v1/auth/cas"):
            var parts = URLComponents(string: "https://atrust.wust.edu.cn/portal/shortcut.html")!
            parts.queryItems = [URLQueryItem(name: "data", value: #"{"env":{"need":true},"ticket":"test-environment-ticket"}"#), URLQueryItem(name: "nextService", value: "auth/authCheck")]
            finalURL = parts.url!
            text = "callback"
        case ("atrust.wust.edu.cn", "/controller/v1/public/reportEnv"):
            text = scenario.reportFailure ? #"{"code":123}"# : #"{"code":0}"#
        case ("atrust.wust.edu.cn", "/passport/v1/auth/authCheck"):
            let object: [String: Any] = ["code": 0, "data": ["sidTicket": "test-sid", "nextService": scenario.nextService]]
            text = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        case ("bkjx.wust.edu.cn", "/jsxsd/"), ("bkjx.wust.edu.cn", "/jsxsd"):
            headers["Set-Cookie"] = "JSESSIONID=test-session; Path=/jsxsd/; Secure"
            text = "base"
        case ("bkjx.wust.edu.cn", "/jsxsd/framework/blankPage.jsp"):
            if scenario.blankPageRedirect {
                scenario.blankPageRedirect = false
                finalURL = URL(string: "https://auth.wust.edu.cn/lyuapServer/login")!
            }
            text = scenario.blankPageBody
        case ("bkjx.wust.edu.cn", "/jsxsd/grxx/xsxx"):
            var rows = Array(repeating: Array(repeating: "synthetic", count: 5), count: 50)
            rows[2] = ["院系：示例院系", "专业：示例专业", "", "班级：示例班级", "学号：" + scenario.studentID]
            text = "<table id='xjkpTable'><tbody>" + rows.map { "<tr>" + $0.map { "<td>" + $0 + "</td>" }.joined() + "</tr>" }.joined() + "</tbody></table>"
        default:
            throw URLError(.unsupportedURL)
        }
        return (HTTPURLResponse(url: finalURL, statusCode: status, httpVersion: nil, headerFields: headers)!, Data(text.utf8), delay)
    }
}

final class LoginTestURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data, delay) = try LoginTestServer.shared.response(request)
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

actor TestCredentialStore: UnionCredentialStore {
    private var credentials: [String: UnionCredential] = [:]
    private(set) var writes = 0
    private var pauseSave = false
    private(set) var saving = false
    private var saveContinuation: CheckedContinuation<Void, Never>?
    func pauseNextSave() { pauseSave = true }
    func resumeSave() { saveContinuation?.resume(); saveContinuation = nil }
    func loadCredential(for username: String) -> UnionCredential? { credentials[username] }
    func saveCredential(_ credential: UnionCredential, for username: String) async {
        if pauseSave {
            pauseSave = false
            saving = true
            await withCheckedContinuation { saveContinuation = $0 }
        }
        credentials[username] = credential
        writes += 1
    }
    func clearCredential(for username: String) { credentials[username] = nil }
}

func testClient(store: TestCredentialStore? = nil, credential: UnionCredential? = UnionCredential(tgt: "TGT-test"), solver: WUSTLoginClient.CaptchaSolver? = nil) throws -> WUSTLoginClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [LoginTestURLProtocol.self]
    return try WUSTLoginClient(username: "test-account", deviceID: "test-device", credential: credential, credentialStore: store, sessionConfiguration: config, captchaSolver: solver ?? { _ in "2" })
}

func isAuthenticated(_ result: WUSTLoginResult) -> Bool {
    if case .authenticated = result { return true }; return false
}
