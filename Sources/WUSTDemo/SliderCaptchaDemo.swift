import Foundation
import WUSTFoundation

enum SliderCaptchaDemo {
    static func run() async throws {
        let solution = try await DemoCaptchaRetry.run(label: "滑块校验") { diagnostics in
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }
            let service = AuthServerCaptchaService()
            try await service.beginSession(using: session, diagnostics: diagnostics)
            return try await service.solveAndVerify(using: session, maxAttempts: 1, diagnostics: diagnostics)
        }
        print("服务器已确认滑块校验成功；匹配置信度：\(String(format: "%.3f", solution.confidence))。")
        print("本次只验证滑块流程，没有提交账号或密码。")
    }
}
