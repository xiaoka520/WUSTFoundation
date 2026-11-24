import Foundation
import Testing
@testable import WUSTFoundation

struct AuthServerLoginTests {
    private let loginURL = URL(string: "https://auth.wust.edu.cn/authserver/login?service=https%3A%2F%2Fbkjx.wust.edu.cn%2Fjsxsd%2F")!
    private let form = """
    <form id="pwdFromId" action="/authserver/login" method="post">
      <input id="pwdEncryptSalt" type="hidden" value="0123456789abcdef">
      <input name="execution" type="hidden" value="test-execution">
      <input name="_eventId" type="hidden" value="submit">
      <input name="cllt" type="hidden" value="userNameLogin">
      <input name="passwordText" type="password">
    </form>
    """

    @Test func formKeepsExecutionAndServiceAndEncryptsPassword() throws {
        let request = try AuthServerLoginService.submission(html: form, loginURL: loginURL,
                                                            username: "test+account", password: "synthetic-password")
        #expect(request.url == loginURL)
        #expect(request.httpMethod == "POST")
        let bodyData = try #require(request.httpBody)
        let body = try #require(String(data: bodyData, encoding: .utf8))
        let values = URLComponents(string: "https://test.invalid/?" + body)?.queryItems ?? []
        let fields = Dictionary(uniqueKeysWithValues: values.map { ($0.name, $0.value ?? "") })
        #expect(fields["username"] == "test+account")
        #expect(fields["execution"] == "test-execution")
        #expect(fields["_eventId"] == "submit")
        #expect(fields["passwordText"] == nil)
        #expect(!body.contains("synthetic-password"))
        let encrypted = try #require(fields["password"])
        #expect(Data(base64Encoded: encrypted) != nil)
    }

    @Test func missingExecutionIsRejectedBeforeCredentialsAreSubmitted() {
        let invalid = form.replacingOccurrences(of: "name=\"execution\"", with: "name=\"other\"")
        #expect(throws: AuthServerLoginError.invalidForm) {
            try AuthServerLoginService.submission(html: invalid, loginURL: loginURL, username: "test", password: "test")
        }
    }

    @Test func foreignFormActionIsRejected() {
        let invalid = form.replacingOccurrences(of: "action=\"/authserver/login\"", with: "action=\"https://other.invalid/authserver/login\"")
        #expect(throws: AuthServerLoginError.invalidForm) {
            try AuthServerLoginService.submission(html: invalid, loginURL: loginURL, username: "test", password: "test")
        }
    }

    @Test func bootstrapHTTPFailureIsNotAuthenticationSuccess() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthServerFailureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        await #expect(throws: AuthServerLoginError.unexpectedStatusCode(503)) {
            try await AuthServerLoginService().login(username: "test", password: "test", using: session)
        }
    }

    @Test func redirectDoesNotForwardCredentialPostToAnotherHost() {
        let policy = AuthServerRedirectPolicy(authenticationHost: "auth.wust.edu.cn")
        var post = URLRequest(url: URL(string: "https://other.invalid/receive")!)
        post.httpMethod = "POST"
        #expect(!policy.permits(post))
        post.httpMethod = "GET"
        #expect(policy.permits(post))
        post.url = URL(string: "http://other.invalid/receive")!
        #expect(!policy.permits(post))
    }
}

private final class AuthServerFailureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "auth.wust.edu.cn" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
