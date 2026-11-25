import Foundation
import Testing
import WUSTFoundation
@testable import WUSTDemo

struct DemoTrajectoryStoreTests {
    private func payload() throws -> SliderCaptchaTrace {
        try JSONDecoder().decode(SliderCaptchaTrace.self, from: Data(#"{"canvasLength":280,"moveLength":99,"tracks":[{"a":0,"b":0,"c":0},{"a":101,"b":3,"c":31},{"a":99,"b":2,"c":47}]}"#.utf8))
    }
    private func records(_ url: URL) throws -> [[String: Any]] {
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(root["source"] as? String == "WUSTDemo")
        return try #require(root["records"] as? [[String: Any]])
    }

    @Test func everyGenerationExistsOnDiskBeforeTheRunFinishes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let diagnostics = DemoCaptchaDiagnostics(trajectoryDirectory: folder)
        diagnostics.begin(1)
        diagnostics.record(.trajectoryPoints(try payload()), attempt: 1)
        let first = try #require(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        #expect(try records(first)[0]["status"] as? String == "generated")
        let json = try #require(try records(first)[0]["payload"] as? [String: Any])
        let restored = try JSONDecoder().decode(SliderCaptchaTrace.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.tracks.map(\.a) == [0, 101, 99])
        #expect(restored.tracks.map(\.b) == [0, 3, 2])
        #expect(restored.tracks.map(\.c) == [0, 31, 47])

        diagnostics.record(.result(code: 0), attempt: 1)
        diagnostics.record(.failure(kind: "SliderCaptchaError.rejected(0)"), attempt: 1)
        #expect(try records(first)[0]["errorCode"] as? Int == 0)
        #expect(try records(first)[0]["status"] as? String == "rejected")
        #expect(try records(first)[0]["failure"] as? String == "SliderCaptchaError.rejected(0)")

        diagnostics.record(.trajectoryPoints(try payload()), attempt: 1)
        diagnostics.begin(2)
        diagnostics.record(.trajectoryPoints(try payload()), attempt: 2)
        diagnostics.record(.failure(kind: "CancellationError"), attempt: 2)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        #expect(files.count == 3)
        #expect(try records(first)[0]["status"] as? String == "rejected")
        let all = try files.flatMap(records)
        #expect(all.contains { $0["status"] as? String == "generated" })
        #expect(all.contains { $0["status"] as? String == "failed" && $0["failure"] as? String == "CancellationError" })
        let attributes = try FileManager.default.attributesOfItem(atPath: first.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func separateRunsDoNotOverwriteAndStorageFailureIsReported() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try DemoTrajectoryStore(directory: folder).append(payload(), attempt: 1)
        let second = try DemoTrajectoryStore(directory: folder).append(payload(), attempt: 1)
        #expect(first != second)
        let invalid = folder.appendingPathComponent("a-file")
        try Data().write(to: invalid)
        #expect(throws: (any Error).self) {
            try DemoTrajectoryStore(directory: invalid).append(payload(), attempt: 1)
        }
    }
}
