import Foundation
import WUSTFoundation

enum NoticePDFPreview {
    static func show(_ document: NoticeDocument, service: NoticeService, session: URLSession) async throws {
        let data = try await service.fetchPDF(document, using: session)
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WUSTDemo-PDF-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            let file = directory.appendingPathComponent("notice.pdf")
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try Task.checkCancellation()
            try await NoticePreviewProcesses.shared.open(file: file, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

private actor NoticePreviewProcesses {
    static let shared = NoticePreviewProcesses()
    private var processes: [UUID: Process] = [:]

    func open(file: URL, directory: URL) throws {
        try Task.checkCancellation()
        let id = UUID()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [self] process in
            let status = process.terminationStatus
            Task { await self.finished(id: id, directory: directory, status: status) }
        }
        try process.run()
        processes[id] = process
    }

    private func finished(id: UUID, directory: URL, status: Int32) {
        processes[id] = nil
        try? FileManager.default.removeItem(at: directory)
        if status != 0 {
            FileHandle.standardOutput.write(Data("系统快速预览进程退出（状态码 \(status)）。\n".utf8))
        }
    }
}
