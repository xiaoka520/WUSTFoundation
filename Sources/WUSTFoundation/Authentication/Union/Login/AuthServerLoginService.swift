import Foundation
import SwiftSoup

public enum AuthServerLoginError: Error, Sendable, Equatable {
    case invalidInput
    case invalidForm
    case invalidResponse
    case unexpectedStatusCode(Int)
    /// The server returned to its authentication UI (rejected credentials or another verification step).
    case loginNotCompleted
}

/// Password login for the new CAS form, including native slider verification.
/// Successful submission is still followed by business-session and account validation in WUSTLoginClient.
public struct AuthServerLoginService: Sendable {
    public init() {}

    public func login(username: String, password: String,
                      service: URL = URL(string: "https://bkjx.wust.edu.cn/jsxsd/")!,
                      using session: URLSession) async throws {
        guard !username.isEmpty, !password.isEmpty,
              service.scheme == "https", service.host != nil else { throw AuthServerLoginError.invalidInput }
        var components = URLComponents(string: "https://auth.wust.edu.cn/authserver/login")!
        components.queryItems = [URLQueryItem(name: "service", value: service.absoluteString)]
        guard let loginURL = components.url else { throw AuthServerLoginError.invalidInput }
        let (data, response) = try await session.data(for: URLRequest(url: loginURL))
        let initial = try Self.http(response)
        if initial.url?.host == service.host { return }
        guard initial.url?.host == loginURL.host,
              data.count < 12_000_000, let html = String(data: data, encoding: .utf8) else {
            throw AuthServerLoginError.invalidResponse
        }
        let submission = try Self.submission(html: html, loginURL: loginURL,
                                             username: username, password: password)
        _ = try await AuthServerCaptchaService().solveAndVerify(using: session)
        let (_, completedResponse) = try await session.data(
            for: submission, delegate: AuthServerRedirectPolicy(authenticationHost: "auth.wust.edu.cn")
        )
        let completed = try Self.http(completedResponse)
        guard completed.url?.host == service.host else { throw AuthServerLoginError.loginNotCompleted }
    }

    static func submission(html: String, loginURL: URL, username: String, password: String) throws -> URLRequest {
        let document = try SwiftSoup.parse(html)
        guard let form = try document.getElementById("pwdFromId"),
              try form.attr("method").lowercased() == "post",
              let saltField = try form.select("input[id=pwdEncryptSalt]").first() else {
            throw AuthServerLoginError.invalidForm
        }
        let salt = try saltField.attr("value")
        guard [16, 24, 32].contains(salt.utf8.count) else { throw AuthServerLoginError.invalidForm }
        let action = try form.attr("action")
        guard let target = URL(string: action, relativeTo: loginURL)?.absoluteURL,
              target.scheme == "https", target.host == loginURL.host,
              target.port == loginURL.port, target.path == loginURL.path else {
            throw AuthServerLoginError.invalidForm
        }
        var fields: [String: String] = [:]
        for input in try form.select("input[type=hidden][name]") {
            fields[try input.attr("name")] = try input.attr("value")
        }
        guard let execution = fields["execution"], !execution.isEmpty,
              fields["_eventId"] == "submit" else { throw AuthServerLoginError.invalidForm }
        fields["username"] = username
        fields["password"] = try AuthServerEncryption.encrypt(Data(password.utf8), key: salt)
        fields["captcha"] = ""
        // passwordText is disabled by the official form before submission; never send plaintext.
        fields.removeValue(forKey: "passwordText")
        var query = URLComponents()
        query.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
        guard let encoded = query.percentEncodedQuery else { throw AuthServerLoginError.invalidForm }
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(loginURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("https://auth.wust.edu.cn", forHTTPHeaderField: "Origin")
        request.httpBody = Data(encoded.replacingOccurrences(of: "+", with: "%2B").utf8)
        return request
    }

    private static func http(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse, response.url != nil else {
            throw AuthServerLoginError.invalidResponse
        }
        guard response.statusCode == 200 else { throw AuthServerLoginError.unexpectedStatusCode(response.statusCode) }
        return response
    }
}

/// CAS redirects normally turn the form POST into a GET. Never forward credentials on a foreign POST.
final class AuthServerRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    let authenticationHost: String
    init(authenticationHost: String) { self.authenticationHost = authenticationHost }

    func permits(_ request: URLRequest) -> Bool {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil else { return false }
        if request.httpMethod != "GET" && request.httpMethod != "HEAD" {
            return url.host == authenticationHost && (url.port == nil || url.port == 443)
        }
        return true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(permits(request) ? request : nil)
    }
}
