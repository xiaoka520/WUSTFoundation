import Foundation
import Testing
@testable import WUSTFoundation

struct AuthServerCredentialErrorTests {
    private let loginURL = URL(string: "https://auth.wust.edu.cn/authserver/login?service=https%3A%2F%2Fbkjx.wust.edu.cn%2Fjsxsd%2F")!
    private let service = URL(string: "https://bkjx.wust.edu.cn/jsxsd/")!
    private func page(_ error: String) -> Data {
        Data("<form id='pwdFromId'><span id='showErrorTip'>\(error)</span></form>".utf8)
    }
    private func response(_ url: URL, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    @Test(arguments: ["用户名或密码错误", "账号或密码错误，请重新输入。", "密码错误！", "Invalid username or password."])
    func explicitRejectionHasItsOwnErrorType(_ message: String) {
        #expect(throws: AuthServerCredentialError.invalidCredentials) {
            try AuthServerPasswordResponse.validate(data: page(message), response: response(loginURL), loginURL: loginURL, service: service)
        }
    }

    @Test(arguments: ["验证码错误", "账号已锁定", "密码错误次数过多，账号已锁定", "密码错误，账号已锁定", "请完成二次认证", "密码已过期", "登录未完成", "注意：用户名或密码错误会导致锁定"])
    func otherFailuresAreNotMislabelledAsBadPassword(_ message: String) {
        #expect(throws: AuthServerLoginError.loginNotCompleted) {
            try AuthServerPasswordResponse.validate(data: page(message), response: response(loginURL), loginURL: loginURL, service: service)
        }
    }

    @Test func placeholderScriptsAndHiddenTextDoNotCountAsARejection() throws {
        let html = """
        <form id='pwdFromId'><input placeholder='用户名或密码错误'>
        <span id='showErrorTip'></span><p>用户名或密码错误</p>
        <script>var unused = '用户名或密码错误';</script>
        <span id='msg' hidden>用户名或密码错误</span></form>
        """
        #expect(try !AuthServerPasswordResponse.explicitlyRejectsCredentials(html))
        #expect(try !AuthServerPasswordResponse.explicitlyRejectsCredentials("<form id='pwdFromId'><span id='showErrorTip'>密码错误</span><div role='alert'>账号已锁定</div></form>"))
    }

    @Test func HTTPAndOriginFailuresKeepTheirOwnMeaning() throws {
        #expect(throws: AuthServerLoginError.unexpectedStatusCode(503)) {
            try AuthServerPasswordResponse.validate(data: page("密码错误"), response: response(loginURL, status: 503), loginURL: loginURL, service: service)
        }
        #expect(throws: AuthServerLoginError.loginNotCompleted) {
            try AuthServerPasswordResponse.validate(data: page("密码错误"), response: response(URL(string: "https://other.invalid/")!), loginURL: loginURL, service: service)
        }
        try AuthServerPasswordResponse.validate(data: page("密码错误"), response: response(service), loginURL: loginURL, service: service)
    }
}
