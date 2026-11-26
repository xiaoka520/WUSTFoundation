import Foundation
import SwiftSoup

public struct AuthServerSMSLoginContext: Sendable, CustomStringConvertible {
    public let resendAfterSeconds: Int?
    let loginURL: URL
    let service: URL
    let fields: [String: String]

    public var description: String { "AuthServerSMSLoginContext" }
}

public enum AuthServerSMSLoginResult: Sendable {
    case authenticated
    case loginNotCompleted(AuthServerSMSLoginContext)
}

public struct AuthServerSMSLoginService: Sendable {
    public init() {}

    public func sendCode(
        account: String,
        service: URL = URL(string: "https://bkjx.wust.edu.cn/jsxsd/")!,
        using session: URLSession,
        maxSliderAttempts: Int = 3,
        diagnostics: (@Sendable (SliderCaptchaDiagnostic) -> Void)? = nil
    ) async throws -> AuthServerSMSLoginContext {
        guard !account.isEmpty, account.count <= 100,
              account.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              service.scheme == "https", service.host != nil else { throw AuthServerLoginError.invalidInput }
        guard (1...5).contains(maxSliderAttempts) else { throw SliderCaptchaError.invalidAttempts }
        var url = URLComponents(string: "https://auth.wust.edu.cn/authserver/login")!
        url.queryItems = [URLQueryItem(name: "service", value: service.absoluteString)]
        guard let loginURL = url.url else { throw AuthServerLoginError.invalidInput }
        var request = URLRequest(url: loginURL)
        AuthServerRequestHeaders.apply(to: &request, ajax: false)
        let (data, response) = try await session.data(for: request)
        let http = try AuthServerLoginService.http(response)
        guard http.url == loginURL, data.count < 12_000_000,
              let html = String(data: data, encoding: .utf8) else { throw AuthServerLoginError.invalidResponse }
        let fields = try Self.formFields(html: html, loginURL: loginURL, account: account)
        _ = try await AuthServerCaptchaService(referer: loginURL).solveAndVerify(
            using: session, maxAttempts: maxSliderAttempts, diagnostics: diagnostics
        )
        try Task.checkCancellation()
        let sms = try Self.codeRequest(account: account, loginURL: loginURL)
        let (sentData, sentResponse) = try await session.data(
            for: sms, delegate: AuthServerRedirectPolicy(authenticationHost: "auth.wust.edu.cn")
        )
        let sentHTTP = try AuthServerLoginService.http(sentResponse)
        guard sentHTTP.url == sms.url else { throw AuthServerLoginError.invalidResponse }
        let result = try JSONDecoder().decode(CodeResponse.self, from: sentData)
        guard result.code == "success" else { throw AuthServerLoginError.smsCodeRejected(result.code) }
        try Task.checkCancellation()
        return AuthServerSMSLoginContext(resendAfterSeconds: result.intervalTime,
                                         loginURL: loginURL, service: service, fields: fields)
    }

    public func login(
        code: String, context: AuthServerSMSLoginContext, using session: URLSession
    ) async throws -> AuthServerSMSLoginResult {
        let request = try Self.submission(code: code, context: context)
        let (data, response) = try await session.data(
            for: request, delegate: AuthServerRedirectPolicy(authenticationHost: "auth.wust.edu.cn")
        )
        let http = try AuthServerLoginService.http(response)
        if http.url?.scheme == context.service.scheme, http.url?.host == context.service.host,
           (http.url?.port ?? 443) == (context.service.port ?? 443) {
            return .authenticated
        }
        guard http.url?.scheme == context.loginURL.scheme, http.url?.host == context.loginURL.host,
              (http.url?.port ?? 443) == (context.loginURL.port ?? 443),
              http.url?.path == context.loginURL.path,
              data.count < 12_000_000, let html = String(data: data, encoding: .utf8),
              let account = context.fields["username"] else { throw AuthServerLoginError.loginNotCompleted }
        let fields = try Self.formFields(html: html, loginURL: context.loginURL, account: account)
        return .loginNotCompleted(AuthServerSMSLoginContext(resendAfterSeconds: context.resendAfterSeconds,
                                                           loginURL: context.loginURL, service: context.service, fields: fields))
    }

    static func formFields(html: String, loginURL: URL, account: String) throws -> [String: String] {
        let document = try SwiftSoup.parse(html)
        guard let form = try document.getElementById("phoneFromId"),
              try form.attr("method").lowercased() == "post",
              let action = URL(string: try form.attr("action"), relativeTo: loginURL)?.absoluteURL,
              action.scheme == loginURL.scheme, action.host == loginURL.host,
              action.port == loginURL.port, action.path == loginURL.path else {
            throw AuthServerLoginError.invalidForm
        }
        var fields: [String: String] = [:]
        for input in try form.select("input[type=hidden][name]") {
            fields[try input.attr("name")] = try input.attr("value")
        }
        guard fields["execution"]?.isEmpty == false, fields["_eventId"] == "submit",
              fields["cllt"] == "dynamicLogin", fields["dllt"] == "generalLogin" else {
            throw AuthServerLoginError.invalidForm
        }
        fields.removeValue(forKey: "password")
        fields.removeValue(forKey: "passwordText")
        fields["username"] = account
        fields["captcha"] = ""
        return fields
    }

    static func codeRequest(account: String, loginURL: URL) throws -> URLRequest {
        let encrypted = try AuthServerEncryption.encrypt(Data(account.utf8), key: "rjBFAaHsNkKAhpoi")
        return try formRequest(url: URL(string: "https://auth.wust.edu.cn/authserver/dynamicCode/getDynamicCode.htl")!,
                               fields: ["mobile": encrypted, "captcha": ""], referer: loginURL, ajax: true)
    }

    static func submission(code: String, context: AuthServerSMSLoginContext) throws -> URLRequest {
        guard !code.isEmpty, code.utf8.count <= 10, code.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw AuthServerLoginError.invalidInput
        }
        var fields = context.fields
        fields["dynamicCode"] = code
        return try formRequest(url: context.loginURL, fields: fields, referer: context.loginURL, ajax: false)
    }

    private static func formRequest(url: URL, fields: [String: String], referer: URL, ajax: Bool) throws -> URLRequest {
        var form = URLComponents()
        form.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
        guard let encoded = form.percentEncodedQuery else { throw AuthServerLoginError.invalidForm }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        AuthServerRequestHeaders.apply(to: &request, ajax: ajax, referer: referer)
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(encoded.replacingOccurrences(of: "+", with: "%2B").utf8)
        return request
    }

    private struct CodeResponse: Decodable {
        let code: String
        let intervalTime: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decode(String.self, forKey: .code)
            if let number = try? container.decode(Int.self, forKey: .intervalTime) {
                intervalTime = number >= 0 ? number : nil
            } else {
                intervalTime = (try? container.decode(String.self, forKey: .intervalTime)).flatMap(Int.init).flatMap { $0 >= 0 ? $0 : nil }
            }
        }

        private enum CodingKeys: String, CodingKey { case code, intervalTime }
    }
}
