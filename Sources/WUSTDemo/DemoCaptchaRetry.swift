import Foundation
import WUSTFoundation

enum DemoCaptchaRetry {
    /// At most three total attempts. Each operation must disable nested slider retries.
    static func run<Value>(label: String, operation: (@escaping @Sendable (SliderCaptchaDiagnostic) -> Void) async throws -> Value) async throws -> Value {
        let diagnostics = DemoCaptchaDiagnostics()
        var attempt = 1
        while true {
            diagnostics.begin(attempt)
            let number = attempt
            diagnostics.note("\(label)：第 \(attempt)/3 次尝试")
            do {
                try Task.checkCancellation()
                let result = try await operation { diagnostics.record($0, attempt: number) }
                save(diagnostics, outcome: "第\(number)次尝试成功")
                return result
            } catch {
                let kind = (error as? URLError).map { "URLError(\($0.code.rawValue))" }
                    ?? (error as? SliderCaptchaError).map { "SliderCaptchaError.\($0)" }
                    ?? String(reflecting: type(of: error))
                diagnostics.record(.failure(kind: kind), attempt: number)
                guard let reason = retryReason(error) else {
                    save(diagnostics, outcome: error is CancellationError ? "取消" : "失败，不自动重试")
                    throw error
                }
                diagnostics.note("\(label)：第 \(attempt)/3 次失败（\(reason)）。")
                guard attempt < 3 else {
                    diagnostics.note("已达到 3 次尝试上限。")
                    diagnostics.report()
                    save(diagnostics, outcome: "3次尝试全部失败")
                    throw error
                }
                attempt += 1
                diagnostics.note("正在重新获取挑战并重试……")
            }
        }
    }

    private static func save(_ diagnostics: DemoCaptchaDiagnostics, outcome: String) {
        let message: String
        do {
            let url = try diagnostics.save(outcome: outcome)
            message = "诊断日志：\(url.path)\n逐次轨迹目录：\(DemoTrajectoryStore.defaultDirectory.path)\n"
        } catch {
            message = "诊断日志保存失败（\(String(reflecting: type(of: error)))）。\n"
        }
        FileHandle.standardError.write(Data(message.utf8))
    }

    private static func retryReason(_ error: any Error) -> String? {
        if let error = error as? SliderCaptchaError {
            switch error {
            case .invalidAttempts: return nil
            // Unreliable-image refreshes (and their separate limit) belong to the library.
            case .invalidImage, .invalidGeometry, .rejected:
                return "滑块校验未完成：\(error)"
            default: return nil
            }
        }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet:
                return "临时网络错误 \(error.code.rawValue)"
            default: return nil
            }
        }
        return nil
    }
}
