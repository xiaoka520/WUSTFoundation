import Foundation
import WUSTFoundation

final class DemoCaptchaDiagnostics: @unchecked Sendable {
    private struct Attempt {
        var started = Date()
        var phase = "初始化"
        var confidence: Double?
        var move: Double?
        var duration: Int?
        var code: Int?
        var verificationCookies: Int?
        var matchingReason: String?
        var skippedChallenges = 0
        var error = "未知"
    }
    private let lock = NSLock()
    private let trajectories: DemoTrajectoryStore
    private var attempts: [Int: Attempt] = [:]
    private var lines = ["WUSTDemo 滑块诊断", "开始时间：\(ISO8601DateFormatter().string(from: Date()))"]

    init(trajectoryDirectory: URL = DemoTrajectoryStore.defaultDirectory) {
        trajectories = DemoTrajectoryStore(directory: trajectoryDirectory)
    }

    func begin(_ number: Int) {
        lock.lock()
        attempts[number] = Attempt()
        lines.append("===== 第 \(number)/3 次尝试 =====")
        lock.unlock()
    }

    func record(_ event: SliderCaptchaDiagnostic, attempt number: Int) {
        lock.lock()
        var value = attempts[number] ?? Attempt()
        let text: String
        switch event {
        case .phase(let phase):
            if phase == .fetch {
                let started = value.started
                let skipped = value.skippedChallenges
                value = Attempt()
                value.started = started
                value.skippedChallenges = skipped
            }
            value.phase = phase.rawValue
            text = "阶段=\(phase.rawValue)"
        case .request(let endpoint, let cookies):
            if endpoint == "common/verifySliderCaptcha.htl" { value.verificationCookies = cookies }
            text = "请求=\(endpoint)，Cookie数量=\(cookies)"
        case .requestProfile(let name):
            text = "请求头配置=\(name)"
        case .httpResponse(let endpoint, let status, let expected, let cookies):
            text = "响应=\(endpoint)，HTTP=\(status)，目标主机一致=\(expected)，Cookie数量=\(cookies)"
        case .challenge(let background, let piece, let width, let y):
            text = "背景=\(background)字节，拼图=\(piece)字节，tagWidth=\(width)，yHeight=\(y)"
        case .match(let pixel, let move, let confidence):
            value.confidence = confidence
            value.move = move
            text = "定位x=\(pixel)，提交位移=\(String(format: "%.2f", move))，匹配分数=\(String(format: "%.3f", confidence))"
        case .trajectory(let count, let duration, let minimum, let maximum):
            value.duration = duration
            text = "轨迹点=\(count)，运动时长=\(duration)ms，纵向范围=\(minimum)...\(maximum)"
        case .trajectoryPoints(let payload):
            if let data = try? JSONEncoder().encode(payload), let json = String(data: data, encoding: .utf8) {
                text = "trajectoryPayload=\(json)"
            } else {
                text = "trajectoryPayload记录失败"
            }
            do {
                let url = try trajectories.append(payload, attempt: number)
                lines.append("轨迹文件：\(url.path)")
            } catch { recordArchiveFailure(error) }
        case .candidates(let pixel, let best, let alternative):
            value.confidence = best
            text = "候选x=\(pixel)，最高分=\(String(format: "%.3f", best))，竞争分数=\(String(format: "%.3f", alternative))，分差=\(String(format: "%.3f", best - alternative))"
        case .matchingRejected(let reason):
            value.matchingReason = reason
            text = "定位停止原因=\(reason)"
        case .challengeDiscarded(let count, let limit):
            value.skippedChallenges = count
            text = "定位不可靠，弃图\(count)/\(limit)，立即换图，不占用校验次数"
        case .result(let code):
            value.code = code
            text = "服务器业务码=\(code)"
            do { try trajectories.result(code, attempt: number) }
            catch { recordArchiveFailure(error) }
        case .failure(let kind):
            if value.error == kind { lock.unlock(); return }
            value.error = kind
            text = "错误类型=\(kind)"
            do { try trajectories.failure(kind, attempt: number) }
            catch { recordArchiveFailure(error) }
        }
        attempts[number] = value
        let elapsed = Int(Date().timeIntervalSince(value.started) * 1000)
        lines.append("[滑块诊断 \(number)/3 +\(elapsed)ms] \(text)")
        lock.unlock()
    }

    /// Caller holds lock; do not log arbitrary error descriptions that might include user data.
    private func recordArchiveFailure(_ error: any Error) {
        let message = "轨迹文件保存失败（\(String(reflecting: type(of: error)))），目录：\(trajectories.directory.path)"
        lines.append(message)
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    func report() {
        lock.lock()
        let snapshot = attempts
        lock.unlock()
        var summary = ["===== 滑块三轮失败汇总 ====="]
        for number in snapshot.keys.sorted() {
            guard let value = snapshot[number] else { continue }
            let score = value.confidence.map { String(format: "%.3f", $0) } ?? "未定位"
            let move = value.move.map { String(format: "%.2f", $0) } ?? "无"
            let duration = value.duration.map(String.init) ?? "无"
            let code = value.code.map(String.init) ?? "未收到业务码"
            summary.append("第\(number)轮：阶段=\(value.phase)，位移=\(move)，分数=\(score)，运动=\(duration)ms，业务码=\(code)，错误=\(value.error)")
            summary.append("本轮跳过不可靠图片：\(value.skippedChallenges)张（不计入校验次数）")
            if let reason = value.matchingReason { summary.append("定位停止原因：\(reason)") }
        }
        if snapshot.count == 3 && snapshot.values.allSatisfy({ $0.code == 0 }) {
            summary.append("三轮均提交到服务器并收到业务拒绝；匹配分数不能证明坐标正确，业务码0也不能单独确定拒绝原因。")
        } else {
            summary.append("按各轮最后阶段区分取图、解码、定位、等待和校验失败；没有业务码表示未取得可解析的校验结果。")
        }
        if snapshot.values.contains(where: { $0.verificationCookies == 0 }) {
            summary.append("存在校验请求Cookie数量为0的情况，需核对会话初始化；此信息本身不能确定失败原因。")
        }
        summary.append("===== 汇总结束（不含图片、密钥或Cookie值） =====")
        lock.lock()
        lines.append(contentsOf: summary)
        lock.unlock()
    }

    func note(_ text: String) {
        lock.lock()
        lines.append(text)
        lock.unlock()
    }

    @discardableResult
    func save(outcome: String, directory: URL? = nil) throws -> URL {
        lock.lock()
        let contents = (lines + ["最终结果：\(outcome)", "结束时间：\(ISO8601DateFormatter().string(from: Date()))"]).joined(separator: "\n") + "\n"
        lock.unlock()
        let folder: URL
        if let directory { folder = directory }
        else {
            folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
                .appendingPathComponent("WUSTDemo/Diagnostics", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent("slider-\(stamp)-\(UUID().uuidString.prefix(8)).log")
        try Data(contents.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
}
