import Foundation
import Testing
@testable import WUSTFoundation

final class LoginTestServer: @unchecked Sendable {
    static let shared = LoginTestServer()
    private let lock = NSLock()
    private var scenario = Scenario()

    struct Scenario {
        var offline = false
        var blankPageBody = ""
        var blankPageRedirect = false
        var delay: TimeInterval = 0
        var studentID = "test-account"
        var avatarJSON = #"{"code":"0","datas":{"headImageIcon":null}}"#
        var avatarLoginRequired = false
        var requests: [URLRequest] = []
    }

    func reset() { lock.lock(); defer { lock.unlock() }; scenario = Scenario() }
    func update(_ body: (inout Scenario) -> Void) { lock.lock(); defer { lock.unlock() }; body(&scenario) }
    func count(_ path: String) -> Int { requests().filter { $0.url?.path == path }.count }
    func requests() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return scenario.requests }

    func response(_ request: URLRequest) throws -> (HTTPURLResponse, Data, TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        scenario.requests.append(request)
        if scenario.offline { throw URLError(.notConnectedToInternet) }
        let url = request.url!
        var finalURL = url
        let text: String
        switch (url.host, url.path) {
        case ("bkjx.wust.edu.cn", "/jsxsd/framework/blankPage.jsp"):
            if scenario.blankPageRedirect { finalURL = URL(string: "https://auth.wust.edu.cn/authserver/login")! }
            text = scenario.blankPageBody
        case ("bkjx.wust.edu.cn", "/jsxsd/grxx/xsxx"):
            var rows = Array(repeating: Array(repeating: "synthetic", count: 5), count: 50)
            rows[2] = ["院系：示例院系", "专业：示例专业", "", "班级：示例班级", "学号：" + scenario.studentID]
            text = "<table id='xjkpTable'><tbody>" + rows.map { "<tr>" + $0.map { "<td>" + $0 + "</td>" }.joined() + "</tr>" }.joined() + "</tbody></table>"
        case ("auth.wust.edu.cn", "/personalInfo/personCenter/index.html"):
            if scenario.avatarLoginRequired { finalURL = URL(string: "https://auth.wust.edu.cn/authserver/login")! }
            text = "<html>personal center</html>"
        case ("auth.wust.edu.cn", "/personalInfo/UserData/user/queryUserData"):
            text = scenario.avatarJSON
        default: throw URLError(.unsupportedURL)
        }
        let headers = url.path.hasSuffix("/queryUserData") ? ["Content-Type": "application/json"] : nil
        return (HTTPURLResponse(url: finalURL, statusCode: 200, httpVersion: nil, headerFields: headers)!, Data(text.utf8), scenario.delay)
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

func testClient(username: String = "test-account") throws -> WUSTLoginClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [LoginTestURLProtocol.self]
    return try WUSTLoginClient(username: username, sessionConfiguration: config)
}

func testUndergraduateCookie() throws -> HTTPCookie {
    try #require(HTTPCookie(properties: [.domain: "bkjx.wust.edu.cn", .path: "/jsxsd/",
                                       .name: "JSESSIONID", .value: "synthetic-session", .secure: "TRUE"]))
}

func isAuthenticated(_ result: WUSTLoginResult) -> Bool {
    if case .authenticated = result { return true }
    return false
}

func waitUntil(_ predicate: @escaping () async -> Bool) async throws {
    for _ in 0..<300 {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw URLError(.timedOut)
}
