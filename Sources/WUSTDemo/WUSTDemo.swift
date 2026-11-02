import Foundation
import Darwin
import WUSTFoundation

@main
struct WUSTDemo {
    enum DemoError: Error { case missingInput, deviceIDStorageUnavailable }

    static func main() async {
        do { try await run() }
        catch let error as URLError {
            log("网络请求失败（URLError \(error.code.rawValue)），未将其判定为凭据失效。")
            exit(EXIT_FAILURE)
        } catch is CancellationError {
            log("操作已取消。")
        } catch let error as WUSTLoginClientError {
            log("登录流程未完成：\(error)。")
            exit(EXIT_FAILURE)
        } catch let error as UnionAuthServiceError {
            switch error {
            case .loginFailed(let code):
                let safeCode = code.range(of: #"\A[A-Z0-9_]{1,32}\z"#, options: .regularExpression) != nil ? code : "UNKNOWN"
                log("统一认证失败（业务码 \(safeCode)）。")
            case .smsCodeRejected(let code, _), .smsVerificationRejected(let code, _):
                log("短信操作被服务器拒绝（业务码 \(code)）。")
            case .unexpectedStatusCode(let code), .configurationRejected(let code):
                log("统一认证请求失败（状态码 \(code)）。")
            default:
                log("统一认证未完成，请检查凭据或验证状态。")
            }
            exit(EXIT_FAILURE)
        } catch let error as ATrustAuthServiceError {
            switch error {
            case .rejected(let code): log("aTrust 拒绝认证（业务码 \(code)）。")
            case .unexpectedStatusCode(let code): log("aTrust 请求失败（HTTP \(code)）。")
            case .requestFailed(_, let status, let code):
                log("aTrust 请求失败（HTTP \(status)，业务码 \(code.map(String.init) ?? "未知")）。")
            default: log("aTrust 响应或回调无效。")
            }
            exit(EXIT_FAILURE)
        } catch let error as UndergraduateAuthServiceError {
            log("教务会话处理失败：\(error)。")
            exit(EXIT_FAILURE)
        } catch let error as DemoCredentialStore.StoreError {
            switch error {
            case .keychain(let status): log("Keychain 操作失败（OSStatus \(status)）。")
            case .invalidData: log("已保存的凭据数据无效，请清除后重新登录。")
            }
            exit(EXIT_FAILURE)
        } catch {
            log("演示未完成，错误类型：\(String(reflecting: type(of: error)))。")
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let username = try input("请输入账号（学号）：")
        let client = try makeClient(username: username)
        log("输入 1 恢复已保存的登录（默认），2 重新登录，3 清除本账号本地登录：")
        let choice = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
        if choice == "3" {
            try await client.logout()
            log("已清除本账号的本地 TGT 和会话；未撤销服务端或其他 App 的登录。")
            return
        }
        var password: String? = nil
        var result: WUSTLoginResult
        if choice == "2" {
            let value = try input("请输入密码：")
            password = value
            log("正在进行统一认证及会话建立……")
            result = try await client.login(password: value)
        } else {
            log("正在尝试复用或恢复登录……")
            result = try await client.ensureSession()
        }
        if case .loginRequired = result {
            let value = try input("没有可用 TGT，或 TGT 已失效。请输入密码：")
            password = value
            result = try await client.login(password: value)
        }
        if case .verificationRequired(_, let methods) = result {
            log("统一认证要求二次验证；可用方式：\(methods.map { $0 == .sms ? "短信" : "微信" }.joined(separator: "、"))")
            guard methods.contains(.sms) else {
                log("当前 Demo 未提供微信验证界面。")
                return
            }
            log("输入 1 发送一次短信验证码，其他输入结束：")
            guard readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) == "1" else { return }
            try await client.sendSMSCode()
            let code = try input("服务器已确认发送，请输入短信验证码：")
            let value: String
            if let password { value = password }
            else { value = try input("请输入密码以继续统一认证：") }
            log("正在校验短信并继续登录……")
            result = try await client.submitSMSCode(code, password: value)
        }
        password = nil
        guard describe(result) else { return }
        _ = try await client.fetchStudentInfo()
        log("学生信息读取成功，学号与登录账号一致。")
        log("输入 1 在全新 client 中恢复，2 再次复用当前会话，3 退出并清除本地凭据，其他输入结束：")
        switch readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "1":
            let restored = try makeClient(username: username)
            guard describe(try await restored.ensureSession()) else { return }
            _ = try await restored.fetchStudentInfo()
            log("全新 client 恢复与学生信息读取成功，未重新输入密码或发送短信。")
        case "2":
            guard describe(try await client.ensureSession()) else { return }
            _ = try await client.fetchStudentInfo()
            log("当前教务会话复用及学生信息读取成功。")
        case "3":
            try await client.logout()
            log("本账号的本地凭据及当前 client 会话已清除。")
        default: break
        }
    }

    private static func makeClient(username: String) throws -> WUSTLoginClient {
        try WUSTLoginClient(
            username: username, deviceID: loadOrCreateATrustDeviceID(),
            credentialStore: DemoCredentialStore()
        )
    }

    private static func describe(_ result: WUSTLoginResult) -> Bool {
        switch result {
        case .authenticated: log("aTrust 与教务会话已就绪。请勿打印 Cookie 或 TGT。") ; return true
        case .loginRequired: log("TGT 不可用，需要重新登录。")
        case .verificationRequired: log("服务器仍要求二次验证，本次演示停止，不自动重复发送短信。")
        case .additionalAuthenticationRequired: log("aTrust 要求尚未接入的后续认证，本次演示停止。")
        }
        return false
    }

    private static func input(_ prompt: String) throws -> String {
        log(prompt)
        guard let value = readLine(), !value.isEmpty else { throw DemoError.missingInput }
        return value
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private static func loadOrCreateATrustDeviceID() throws -> String {
        guard let preferences = UserDefaults(suiteName: "WUSTFoundation.WUSTDemo") else {
            throw DemoError.deviceIDStorageUnavailable
        }
        let key = "ATrustDeviceID"
        if let saved = preferences.string(forKey: key), !saved.isEmpty { return saved }
        let value = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        preferences.set(value, forKey: key)
        return value
    }
}
