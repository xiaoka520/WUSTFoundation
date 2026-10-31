import Foundation
import Darwin
import WUSTFoundation

public enum DemoError: Error {
    case invalidCaptchaImage
    case missingInput(String)
    case captchaRecognitionExhausted
    case unexpectedATrustCallback
    case invalidATrustAuthenticationResponse
    case missingATrustEnvironmentTicket
    case deviceIDStorageUnavailable
    case studentIDMismatch
}

@main
struct WUSTDemo {
    static func main() async {
        do {
            try await run()
        } catch {
            print("演示未完成：\(error)")
            exit(EXIT_FAILURE)
        }
    }

    private static func fetchRecognizedCaptcha(
        using session: URLSession,
        authService: UnionAuthService
    ) async throws -> (LoginCaptcha, String) {
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            print("正在识别图形验证码（\(attempt)/\(maxAttempts)）……")
            let captcha = try await authService.fetchCaptcha(using: session)
            let parts = captcha.content.split(separator: ",", maxSplits: 1)
            guard parts.count == 2,
                  let imageData = Data(base64Encoded: String(parts[1])) else {
                throw DemoError.invalidCaptchaImage
            }
            do {
                let code = try VisionCaptchaSolver().solve(imageData: imageData)
                return (captcha, code)
            } catch let error as CaptchaRecognitionError {
                print("本张验证码识别失败：\(error)")
                if attempt < maxAttempts {
                    print("正在更换验证码图片……")
                }
            }
        }
        throw DemoError.captchaRecognitionExhausted
    }

    private static func run() async throws {
        print("请输入账号（学号）：")
        guard let username = readLine(), !username.isEmpty else {
            throw DemoError.missingInput("账号")
        }
        print("请输入密码：")
        guard let password = readLine(), !password.isEmpty else {
            throw DemoError.missingInput("密码")
        }
        let session = URLSession(configuration: .ephemeral)
        defer {
            session.finishTasksAndInvalidate()
        }

        print("正在获取认证入口……")
        let service = try await ATrustAuthService()
            .fetchCASService(using: session)
        let authService = UnionAuthService()
        let (captcha, captchaCode) = try await fetchRecognizedCaptcha(
            using: session,
            authService: authService
        )

        print("正在进行统一认证……")
        let result = try await authService.beginLogin(
            username: username,
            password: password,
            service: service,
            captcha: captcha,
            captchaCode: captchaCode,
            using: session
        )

        switch result {
        case .authenticated(let credential):
            print("已获得 TGT，正在申请 ST……")
            let ticket = try await authService.fetchServiceTicket(
                credential: credential,
                service: service,
                using: session
            )
            print("已获得 TGT，并成功换取 ST")
            try await continueATrustLogin(
                ticket: ticket,
                service: service,
                username: username,
                credential: credential,
                using: session
            )

        case .verificationRequired(let challenge):
            print("统一认证要求二次验证")
            let configuration = try await authService.fetchLoginConfiguration(
                using: session
            )
            let methods = try authService.availableVerificationMethods(
                for: challenge,
                configuration: configuration
            )
            guard !methods.isEmpty else {
                print("本次挑战没有识别到支持的验证方式，认证尚未完成。")
                return
            }
            let names = methods.map { method in
                switch method {
                case .sms: return "短信"
                case .wechat: return "微信"
                }
            }
            print("可用验证方式：\(names.joined(separator: "、"))")
            guard methods.contains(.sms) else {
                print("本次挑战不支持短信，微信验证尚未接入。")
                return
            }
            print("输入 1 发送短信验证码，其他输入结束演示：")
            guard readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) == "1" else {
                print("演示结束，未发送短信。")
                return
            }
            print("正在请求发送短信验证码……")
            try await authService.sendSMSCode(
                username: username,
                challenge: challenge,
                configuration: configuration,
                using: session
            )
            print("服务器已确认发送，请查看手机短信。")
            print("请输入短信验证码，直接回车结束演示：")
            guard let smsCode = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !smsCode.isEmpty else {
                print("演示结束，未提交验证码。")
                return
            }
            print("正在校验短信验证码……")
            try await authService.verifySMSCode(
                username: username,
                code: smsCode,
                service: service,
                challenge: challenge,
                configuration: configuration,
                using: session
            )
            print("验证码校验通过。")
            print("正在继续统一认证，获取登录凭据……")
            let (nextCaptcha, nextCaptchaCode) = try await fetchRecognizedCaptcha(
                using: session,
                authService: authService
            )
            let resumedResult = try await authService.beginLogin(
                username: username,
                password: password,
                service: service,
                captcha: nextCaptcha,
                captchaCode: nextCaptchaCode,
                using: session
            )
            switch resumedResult {
            case .authenticated(let credential):
                print("验证后已获得 TGT，正在申请 ST……")
                let ticket = try await authService.fetchServiceTicket(
                    credential: credential,
                    service: service,
                    using: session
                )
                print("短信校验、TGT 获取和 ST 换票均已完成。")
                try await continueATrustLogin(
                    ticket: ticket,
                    service: service,
                    username: username,
                    credential: credential,
                    using: session
                )

            case .verificationRequired:
                print("短信校验已通过，但继续登录仍要求二次验证，尚未取得 TGT。")
                print("本次演示结束，需要进一步核对验证后的登录衔接。")
            }
        }
    }

    private static func continueATrustLogin(
        ticket: String,
        service: String,
        username: String,
        credential: UnionCredential,
        using session: URLSession
    ) async throws {
        let authService = ATrustAuthService()
        print("正在将 ST 提交给 aTrust……")
        let (_, response) = try await authService.exchangeCASTicket(
            ticket: ticket,
            service: service,
            using: session
        )
        guard let url = response.url,
              url.scheme == "https",
              url.host == "atrust.wust.edu.cn",
              url.path == "/portal/shortcut.html",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DemoError.unexpectedATrustCallback
        }

        print("已收到 aTrust 回调；正在判断后续步骤。")
        let queryItems = components.queryItems ?? []
        guard !queryItems.contains(where: { $0.name == "type" && $0.value == "common_error" }),
              !queryItems.contains(where: { $0.name == "err_info" && $0.value?.isEmpty == false }) else {
            print("aTrust 回调包含错误信息，认证尚未完成。")
            throw DemoError.unexpectedATrustCallback
        }
        let environmentTicket = try readEnvironmentTicket(from: components)
        if let environmentTicket {
            let deviceID = try loadOrCreateATrustDeviceID()
            print("正在上报 aTrust 环境信息……")
            try await authService.reportEnvironment(
                environmentTicket: environmentTicket,
                deviceID: deviceID,
                using: session
            )
            print("aTrust 环境上报已通过。")
        }
        // 回调参数可能包含身份凭据，只输出已知步骤的固定说明。
        let nextServices = components.queryItems?.filter { $0.name == "nextService" } ?? []
        guard nextServices.count == 1, let nextService = nextServices.first?.value,
              !nextService.isEmpty else {
            print("回调未提供明确的下一步，aTrust 登录状态尚未确认。")
            return
        }
        switch nextService {
        case "auth/authCheck":
            print("正在检查 aTrust 认证状态……")
            let (data, authResponse) = try await authService.checkAuthentication(using: session)
            guard let authURL = authResponse.url,
                  authURL.scheme == "https",
                  authURL.host == "atrust.wust.edu.cn",
                  authURL.path == "/passport/v1/auth/authCheck" else {
                throw DemoError.unexpectedATrustCallback
            }
            let authenticated = try printATrustAuthenticationSummary(
                data: data,
                redacting: [username, ticket] + [environmentTicket].compactMap { $0 }
            )
            guard authenticated else { return }

            print("正在使用已有 TGT 申请教务票据并建立会话……")
            let cookie = try await UndergraduateAuthService().login(
                credential: credential,
                using: session
            )
            print("已取得教务 Cookie，并通过现有的教务会话检查。")

            print("正在读取学生信息页面……")
            let studentInfo = try await StudentInfoService().fetchStudentInfo(
                cookie: cookie,
                using: session
            )
            print("学生信息读取及解析成功。")
            let studentIDMatches = studentInfo.studentID == username
            print("学号与登录账号匹配：\(studentIDMatches ? "是" : "否")")
            guard studentIDMatches else {
                throw DemoError.studentIDMismatch
            }
            print("本次演示完成：登录并读取学生信息的流程已连通。")
        default:
            print("aTrust 返回了尚未接入的认证步骤，登录尚未完成。")
        }
    }

    private static func loadOrCreateATrustDeviceID() throws -> String {
        guard let preferences = UserDefaults(suiteName: "WUSTFoundation.WUSTDemo") else {
            throw DemoError.deviceIDStorageUnavailable
        }
        let key = "ATrustDeviceID"
        if let deviceID = preferences.string(forKey: key), !deviceID.isEmpty {
            return deviceID
        }
        // Demo 持有可复用的随机客户端标识，不采集硬件信息或保存登录凭据。
        let deviceID = (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        preferences.set(deviceID, forKey: key)
        return deviceID
    }

    private static func readEnvironmentTicket(from components: URLComponents) throws -> String? {
        guard let value = components.queryItems?.first(where: { $0.name == "data" })?.value,
              !value.isEmpty else {
            print("aTrust 回调未携带非空 data 参数。")
            return nil
        }
        guard let callback = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any] else {
            throw DemoError.invalidATrustAuthenticationResponse
        }
        let structure = try JSONSerialization.data(
            withJSONObject: jsonStructure(of: callback), options: [.sortedKeys]
        )
        print("aTrust 回调 data 结构：\(String(decoding: structure, as: UTF8.self))")
        let environment = callback["env"] as? [String: Any]
        let needsEnvironment = environment?["need"] as? Bool
        let hasTicket = (callback["ticket"] as? String)?.isEmpty == false
        print("aTrust 回调 env.need：\(needsEnvironment.map(String.init) ?? "未提供")，携带环境票据：\(hasTicket)")
        guard needsEnvironment == true else { return nil }
        guard let ticket = callback["ticket"] as? String,
              !ticket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DemoError.missingATrustEnvironmentTicket
        }
        return ticket
    }

    private static func printATrustAuthenticationSummary(data: Data, redacting values: [String]) throws -> Bool {
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DemoError.invalidATrustAuthenticationResponse
        }
        if let code = result["code"] as? Int {
            print("aTrust authCheck 业务码：\(code)")
        } else {
            print("aTrust authCheck 未返回整数业务码，需核对响应结构。")
        }
        if let message = result["message"] as? String, !message.isEmpty {
            var redacted = message
            for value in values where !value.isEmpty {
                redacted = redacted.replacingOccurrences(of: value, with: "[已隐藏]")
            }
            let patterns = [
                #"https?://\S+"#,
                #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
                #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#,
                #"[A-Za-z0-9_+/=-]{20,}"#,
                #"\d{6,}"#
            ]
            for pattern in patterns {
                redacted = redacted.replacingOccurrences(
                    of: pattern, with: "[已隐藏]", options: .regularExpression
                )
            }
            print("aTrust 提示（脱敏）：\(String(redacted.prefix(300)))")
        }

        // 仅输出字段名与类型，不输出身份信息、令牌或服务端消息。
        let structure = jsonStructure(of: result)
        let structureData = try JSONSerialization.data(
            withJSONObject: structure,
            options: [.sortedKeys]
        )
        print("aTrust 响应结构：\(String(decoding: structureData, as: UTF8.self))")

        let details = result["data"] as? [String: Any]
        if (result["code"] as? Int) == 0,
           let nextService = details?["nextService"] as? String,
           nextService.isEmpty,
           let sidTicket = details?["sidTicket"] as? String,
           !sidTicket.isEmpty {
            print("aTrust 本次身份认证已完成，无后续认证步骤。")
            return true
        }
        if let services = details?["nextServiceList"] as? [[String: Any]] {
            print("aTrust 候选步骤包含 CAS：\(services.contains { $0["authType"] as? String == "auth/cas" })")
        }
        if let nextService = (details?["nextService"] ?? result["nextService"]) as? String,
           !nextService.isEmpty {
            // 只允许输出步骤路径，避免将任意 URL 或令牌当作步骤名称输出。
            if nextService.range(
                of: #"\Aauth/[A-Za-z][A-Za-z0-9]{0,47}\z"#,
                options: .regularExpression
            ) != nil {
                print("aTrust 下一步：\(nextService)")
            } else {
                print("aTrust 返回了其他后续步骤，具体值未输出。")
            }
        } else {
            print("authCheck 未返回非空的 nextService，仍需结合业务码和响应结构判断状态。")
        }
        print("本次演示已执行 authCheck；aTrust 后续步骤及教务会话尚未完成。")
        return false
    }

    private static func jsonStructure(of value: Any, depth: Int = 0) -> Any {
        guard depth < 5 else { return "更深层结构已省略" }
        if let object = value as? [String: Any] {
            return object.mapValues { jsonStructure(of: $0, depth: depth + 1) }
        }
        if let array = value as? [Any] {
            return array.prefix(3).map { jsonStructure(of: $0, depth: depth + 1) }
        }
        if value is NSNull { return "null" }
        if value is String { return "String" }
        if value is NSNumber { return "Number/Bool" }
        return "其他类型"
    }
}
