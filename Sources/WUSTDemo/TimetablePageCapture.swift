import Foundation
import CryptoKit
import WUSTFoundation

struct TimetableCaptureResult {
    let entryURL: URL
    let semesterURL: URL
    let weekURL: URL?
    let weeklyContentChanged: Bool?
}

enum TimetablePageCapture {
    typealias CaptureError = TimetableCaptureError

    static func capture(
        credential: UnionCredential,
        deviceID: String,
        choose: @Sendable (TimetableCaptureForm) throws -> TimetableCaptureSelection,
        onSaved: @Sendable (URL) -> Void
    ) async throws -> TimetableCaptureResult {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let authentication = try await ATrustAuthService().login(
            credential: credential, deviceID: deviceID, using: session
        )
        guard authentication.isAuthenticated else { throw CaptureError.authenticationRequired }
        let cookie = try await UndergraduateAuthService().login(credential: credential, using: session)
        guard let url = URL(string: "https://bkjx.wust.edu.cn/jsxsd/xskb/xskb_list.do") else {
            throw CaptureError.invalidResponse
        }
        var entryRequest = URLRequest(url: url)
        entryRequest.httpMethod = "GET"
        entryRequest.cachePolicy = .reloadIgnoringLocalCacheData
        entryRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        let groupID = UUID().uuidString.lowercased()
        let (entryData, entryResponse) = try await fetch(entryRequest, using: session)
        let entryForm = try? TimetableCaptureForm.parse(data: entryData, sourceURL: url)
        let entryURL = try save(entryData, response: entryResponse, request: entryRequest,
                                name: "entry-" + groupID, form: entryForm)
        onSaved(entryURL)
        guard let entryForm else { throw CaptureError.formNotFound }
        let selection = try choose(entryForm)
        let semesterSelection = TimetableCaptureSelection(termID: selection.termID, week: "", templateID: selection.templateID)
        let request = try entryForm.makeRequest(selection: semesterSelection, cookie: try currentCookie(using: session, url: url))
        let (semesterData, semesterResponse) = try await fetch(request, using: session)
        let semesterForm = try? TimetableCaptureForm.parse(data: semesterData, sourceURL: url)
        let semesterURL = try save(semesterData, response: semesterResponse, request: request,
            name: "semester-" + groupID, form: semesterForm, selection: semesterSelection, entryFile: entryURL.lastPathComponent)
        onSaved(semesterURL)
        guard let semesterForm, semesterForm.reflects(semesterSelection) else { throw CaptureError.selectionNotReflected }
        guard !selection.week.isEmpty else {
            return TimetableCaptureResult(entryURL: entryURL, semesterURL: semesterURL, weekURL: nil, weeklyContentChanged: nil)
        }
        let weeklyRequest = try semesterForm.makeRequest(selection: selection, cookie: try currentCookie(using: session, url: url))
        let (weekData, weekResponse) = try await fetch(weeklyRequest, using: session)
        let weekForm = try? TimetableCaptureForm.parse(data: weekData, sourceURL: url)
        let weekURL = try save(weekData, response: weekResponse, request: weeklyRequest,
            name: "week-" + groupID, form: weekForm, selection: selection, entryFile: entryURL.lastPathComponent,
            comparison: semesterForm)
        onSaved(weekURL)
        guard let weekForm, weekForm.reflects(selection) else { throw CaptureError.selectionNotReflected }
        return TimetableCaptureResult(entryURL: entryURL, semesterURL: semesterURL, weekURL: weekURL,
            weeklyContentChanged: semesterForm.gridDigest != weekForm.gridDigest)
    }

    private static func fetch(_ request: URLRequest, using session: URLSession) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CaptureError.invalidResponse }
        guard response.statusCode == 200 else { throw CaptureError.unexpectedStatusCode(response.statusCode) }
        guard let requested = request.url, let final = response.url,
              final.scheme == requested.scheme, final.host == requested.host,
              final.port == requested.port, final.path == requested.path else { throw CaptureError.unexpectedRedirect }
        return (data, response)
    }

    private static func currentCookie(using session: URLSession, url: URL) throws -> String {
        let cookies = session.configuration.httpCookieStorage?.cookies(for: url) ?? []
        guard !cookies.isEmpty, let value = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], !value.isEmpty else {
            throw CaptureError.authenticationRequired
        }
        return value
    }

    private static func save(
        _ data: Data, response: HTTPURLResponse, request: URLRequest, name: String,
        form: TimetableCaptureForm?, selection: TimetableCaptureSelection? = nil,
        entryFile: String? = nil, comparison: TimetableCaptureForm? = nil
    ) throws -> URL {
        let packageDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manager = FileManager.default
        guard manager.fileExists(atPath: packageDirectory.appendingPathComponent("Package.swift").path) else {
            throw CaptureError.sourceDirectoryUnavailable
        }
        let directory = packageDirectory.appendingPathComponent("TestData/timetable/captured", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let htmlURL = directory.appendingPathComponent(name + ".html")
        var metadata: [String: Any] = [
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "requestURL": request.url?.absoluteString ?? "unknown", "requestMethod": request.httpMethod ?? "unknown",
            "httpStatus": response.statusCode, "mimeType": response.mimeType ?? "unknown",
            "contentType": response.value(forHTTPHeaderField: "Content-Type") ?? "unknown",
            "textEncodingName": response.textEncodingName ?? "not-declared",
            "validUTF8": String(data: data, encoding: .utf8) != nil, "byteCount": data.count,
            "hasTimetableStructure": form != nil, "validatedAsTimetable": false,
            "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        ]
        if let entryFile { metadata["sourceEntryFile"] = entryFile }
        if let form { metadata["formSummary"] = form.summary }
        if let selection {
            metadata["submittedSelection"] = ["termID": selection.termID, "week": selection.week, "templateID": selection.templateID]
            metadata["selectionReflected"] = form?.reflects(selection) ?? false
        }
        if let comparison, let form { metadata["gridChangedFromSemester"] = comparison.gridDigest != form.gridDigest }
        try data.write(to: htmlURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: htmlURL.path)
        let metadataURL = htmlURL.deletingPathExtension().appendingPathExtension("json")
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: metadataURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataURL.path)
        return htmlURL
    }
}
