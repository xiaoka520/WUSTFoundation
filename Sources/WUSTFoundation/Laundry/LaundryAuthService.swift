import Foundation

public enum LaundryAuthError: Error, Equatable {
    case invalidPhoneNumber
    case invalidSMSCode
    case captchaRequired
    case loginRequired
    case unexpectedStatusCode(Int)
    case rejected(Int)
    case invalidResponse
    case accountMismatch
    case unexpectedWebOrigin
}

public struct LaundryAuthService: Sendable {
    private let api: LaundryAPI

    public init() {
        api = LaundryAPI(profile: .iosApp)
    }

    public init(session: URLSession) {
        api = LaundryAPI(profile: .iosApp, session: session)
    }

    public func sendSMSCode(to phone: String) async throws {
        try validatePhone(phone)
        let preflight: Bool? = try await post("common/isNeedCaptcha", fields: ["phone": phone])
        guard let needsCaptcha = preflight else { throw LaundryAuthError.invalidResponse }
        guard !needsCaptcha else { throw LaundryAuthError.captchaRequired }
        let _: EmptyPayload? = try await post("common/sms/sendCode", fields: [
            "phone": phone, "template": "reg",
        ])
    }

    public func login(phone: String, smsCode: String) async throws -> LaundryCredential {
        try validatePhone(phone)
        guard !smsCode.isEmpty, smsCode.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw LaundryAuthError.invalidSMSCode
        }
        let response: LoginPayload? = try await post("user/reg", fields: [
            "channel": "ios_app", "phone": phone, "verify": smsCode,
        ])
        guard let token = response?.token, !token.isEmpty else { throw LaundryAuthError.invalidResponse }
        return try await validate(token: token)
    }

    public func validate(token: String) async throws -> LaundryCredential {
        let userID = try await fetchUserID(token: token)
        let now = Date()
        return LaundryCredential(userID: userID, firstVerifiedAt: now, lastVerifiedAt: now, token: token)
    }

    public func restore(_ credential: LaundryCredential) async throws -> LaundryCredential {
        let userID = try await fetchUserID(token: credential.token)
        guard userID == credential.userID else { throw LaundryAuthError.accountMismatch }
        return LaundryCredential(
            userID: userID, firstVerifiedAt: credential.firstVerifiedAt,
            lastVerifiedAt: Date(), token: credential.token
        )
    }

    private func fetchUserID(token: String) async throws -> String {
        guard !token.isEmpty else { throw LaundryAuthError.loginRequired }
        let response: UserPayload? = try await post("user/info", fields: ["token": token])
        guard let id = response?.id, !id.isEmpty else { throw LaundryAuthError.invalidResponse }
        return id
    }

    private func validatePhone(_ phone: String) throws {
        guard phone.utf8.count == 11, phone.first == "1", phone.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw LaundryAuthError.invalidPhoneNumber
        }
    }

    private func post<Payload: Decodable>(_ path: String, fields: [String: String]) async throws -> Payload? {
        do {
            return try await api.post(path, fields: fields)
        } catch LaundryQueryError.rejected(2) where path == "user/info" {
            throw LaundryAuthError.loginRequired
        } catch LaundryQueryError.rejected(let code) {
            throw LaundryAuthError.rejected(code)
        } catch LaundryQueryError.unexpectedStatusCode(let status) {
            throw LaundryAuthError.unexpectedStatusCode(status)
        } catch LaundryQueryError.invalidResponse {
            throw LaundryAuthError.invalidResponse
        }
    }

    private struct EmptyPayload: Decodable {
        init(from decoder: Decoder) throws {}
    }

    private struct LoginPayload: Decodable {
        let token: String
    }

    private struct UserPayload: Decodable {
        let id: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let textID = try? container.decode(String.self, forKey: .id) {
                id = textID
            } else {
                id = String(try container.decode(Int64.self, forKey: .id))
            }
        }

        private enum CodingKeys: String, CodingKey { case id }
    }
}
