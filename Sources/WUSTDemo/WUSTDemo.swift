import Foundation
import Darwin
import WUSTFoundation

public enum DemoError: Error {
    case invalidCaptchaImage
    case missingInput(String)
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

    private static func run() async throws {
        print("请输入账号：")
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
        let captcha = try await authService.fetchCaptcha(using: session)

        let parts = captcha.content.split(separator: ",", maxSplits: 1)
        guard parts.count == 2 else {
            throw DemoError.invalidCaptchaImage
        }
        guard let imageData = Data(base64Encoded: String(parts[1])) else {
            throw DemoError.invalidCaptchaImage
        }
        let captchaCode = try VisionCaptchaSolver().solve(imageData: imageData)

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
            _ = try await authService.fetchServiceTicket(
                credential: credential,
                service: service,
                using: session
            )
            print("已获得 TGT，并成功换取 ST")
            print("本次演示完成；aTrust 后续认证尚未接入。")

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
            print("本次演示到此结束；验证码提交接口尚未接入。")
        }
    }
}
