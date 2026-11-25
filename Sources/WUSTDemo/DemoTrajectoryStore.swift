import Foundation
import WUSTFoundation

/// Access is serialized by DemoCaptchaDiagnostics' lock. Writes happen before record() returns.
final class DemoTrajectoryStore {
    private struct Record: Codable {
        let payload: SliderCaptchaTrace
        let attempt: Int
        let generatedAt: String
        var status = "generated"
        var errorCode: Int?
        var failure: String?
    }
    private struct Archive: Encodable {
        let source = "WUSTDemo"
        let schemaVersion = 1
        let records: [Record]
    }
    private struct Entry {
        let url: URL
        var record: Record
    }
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WUSTDemo/Diagnostics/Trajectories", isDirectory: true)
    }
    let directory: URL
    private let runID: String
    private var current: [Int: Entry] = [:]
    private var counts: [Int: Int] = [:]

    init(directory: URL = defaultDirectory) {
        self.directory = directory
        runID = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            + "-" + UUID().uuidString
    }

    @discardableResult
    func append(_ payload: SliderCaptchaTrace, attempt: Int) throws -> URL {
        let count = (counts[attempt] ?? 0) + 1
        counts[attempt] = count
        let url = directory.appendingPathComponent("trace-\(runID)-round\(attempt)-\(count).json")
        let entry = Entry(url: url, record: Record(payload: payload, attempt: attempt,
            generatedAt: ISO8601DateFormatter().string(from: Date())))
        // Keep this entry even if writing fails, so a later result can retry saving it.
        current[attempt] = entry
        try write(entry)
        return url
    }

    func result(_ code: Int, attempt: Int) throws {
        guard var entry = current[attempt] else { return }
        entry.record.errorCode = code
        entry.record.status = code == 1 ? "accepted" : "rejected"
        current[attempt] = entry
        try write(entry)
    }

    func failure(_ kind: String, attempt: Int) throws {
        guard var entry = current[attempt] else { return }
        entry.record.failure = kind
        if entry.record.errorCode == nil { entry.record.status = "failed" }
        current[attempt] = entry
        try write(entry)
    }

    private func write(_ entry: Entry) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Archive(records: [entry.record]))
        try data.write(to: entry.url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: entry.url.path)
    }
}
