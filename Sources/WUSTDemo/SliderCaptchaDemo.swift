import Foundation
import WUSTFoundation

enum SliderCaptchaDemo {
    static func run() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let service = AuthServerCaptchaService()
        print("正在建立新版认证会话并自动校验滑块……")
        try await service.beginSession(using: session)
        let solution = try await service.solveAndVerify(using: session)
        print("服务器已确认滑块校验成功；匹配置信度：\(String(format: "%.3f", solution.confidence))。")
        print("本次只验证滑块流程，没有提交账号或密码。")
    }
}
