import Foundation
import SwiftSoup

/// Only emitted when the school's password-login response explicitly rejects the credentials.
/// A CAPTCHA failure, network error, account lock, or another authentication step is not this error.
public enum AuthServerCredentialError: Error, Sendable, Equatable, LocalizedError {
    case invalidCredentials

    public var errorDescription: String? { "账号或密码错误，请检查后重试。" }
}

enum AuthServerPasswordResponse {
    static func validate(data: Data, response: URLResponse, loginURL: URL, service: URL) throws {
        let response = try AuthServerLoginService.http(response)
        guard let url = response.url, url.scheme == "https" else { throw AuthServerLoginError.invalidResponse }
        if url.host == service.host { return }
        guard url.host == loginURL.host, url.port == loginURL.port, url.path == loginURL.path else {
            throw AuthServerLoginError.loginNotCompleted
        }
        guard data.count < 12_000_000, let html = String(data: data, encoding: .utf8) else {
            throw AuthServerLoginError.invalidResponse
        }
        if try explicitlyRejectsCredentials(html) { throw AuthServerCredentialError.invalidCredentials }
        throw AuthServerLoginError.loginNotCompleted
    }

    static func explicitlyRejectsCredentials(_ html: String) throws -> Bool {
        let document = try SwiftSoup.parse(html)
        guard try document.getElementById("pwdFromId") != nil else { return false }
        let knownMessages: Set<String> = [
            "用户名或密码错误", "用户名或密码有误", "用户名密码错误",
            "账号或密码错误", "账户或密码错误", "密码错误", "密码不正确",
            "invalid username or password", "invalid credentials"
        ]
        // Inspect designated error regions only; never infer failure from a placeholder/script.
        var messages: [String] = []
        for element in try document.select("#showErrorTip, #msg, .login-error, [role=alert]") {
            if element.hasAttr("hidden") { continue }
            let style = try element.attr("style").filter { !$0.isWhitespace }.lowercased()
            if style.contains("display:none") || style.contains("visibility:hidden") { continue }
            messages.append(try element.text().trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        // An accompanying lock/expiry/verification notice takes precedence over a password hint.
        let otherCauses = ["锁定", "冻结", "禁用", "停用", "已过期", "密码过期", "验证码", "二次认证", "多因素", "locked", "disabled", "expired", "captcha", "two-factor"]
        if messages.contains(where: { text in otherCauses.contains(where: { text.contains($0) }) }) { return false }
        for text in messages {
            let firstSentence = text.components(separatedBy: CharacterSet(charactersIn: "，,。.!！；;\n"))[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if knownMessages.contains(firstSentence) { return true }
        }
        return false
    }
}
