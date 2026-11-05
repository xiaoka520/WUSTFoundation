import Foundation
import CryptoKit
import SwiftSoup

enum TimetableCaptureError: Error {
    case authenticationRequired
    case invalidResponse
    case unexpectedStatusCode(Int)
    case unexpectedRedirect
    case sourceDirectoryUnavailable
    case invalidEncoding
    case formNotFound
    case unsupportedForm
    case invalidSelection
    case selectionNotReflected
}

struct TimetableCaptureOption: Sendable {
    let value: String
    let title: String
}

struct TimetableCaptureSelection: Sendable {
    let termID: String
    let week: String
    let templateID: String
}

struct TimetableCaptureForm: Sendable {
    let actionURL: URL
    let fields: [URLQueryItem]
    let terms: [TimetableCaptureOption]
    let weeks: [TimetableCaptureOption]
    let templates: [TimetableCaptureOption]
    let detailedCellCount: Int
    let occupiedCellCount: Int
    let gridDigest: String

    var selectedTermID: String? { value("xnxq01id") }
    var selectedWeek: String? { value("zc") }
    var selectedTemplateID: String? { value("kbjcmsid") }

    func value(_ name: String) -> String? { fields.first { $0.name == name }?.value }

    static func parse(data: Data, sourceURL: URL) throws -> Self {
        guard let html = String(data: data, encoding: .utf8) else { throw TimetableCaptureError.invalidEncoding }
        let document = try SwiftSoup.parse(html)
        guard let form = try document.select("form#Form1").first(),
              try document.getElementById("kbtable") != nil else {
            throw TimetableCaptureError.formNotFound
        }
        guard try form.attr("method").lowercased() == "post" else { throw TimetableCaptureError.unsupportedForm }
        let action = try form.attr("action").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedURL = action.isEmpty ? sourceURL : URL(string: action, relativeTo: sourceURL)?.absoluteURL
        guard let url = resolvedURL,
              url.scheme == sourceURL.scheme, url.host == sourceURL.host,
              url.port == sourceURL.port, url.path == sourceURL.path else {
            throw TimetableCaptureError.unexpectedRedirect
        }
        var fields: [URLQueryItem] = []
        for control in try form.select("input, select, textarea") {
            let name = try control.attr("name")
            guard !name.isEmpty, !control.hasAttr("disabled") else { continue }
            switch control.tagName() {
            case "select":
                let options = try control.select("option").array().filter { !$0.hasAttr("disabled") }
                let selected = options.filter { $0.hasAttr("selected") }
                let values = control.hasAttr("multiple") ? selected : Array((selected.isEmpty ? options : selected).prefix(1))
                for option in values {
                    let value = try option.hasAttr("value") ? option.attr("value") : option.text()
                    fields.append(URLQueryItem(name: name, value: value))
                }
            case "input":
                let type = try control.attr("type").lowercased()
                if ["submit", "button", "reset", "file", "image"].contains(type) { continue }
                if ["checkbox", "radio"].contains(type), !control.hasAttr("checked") { continue }
                let value = try !control.hasAttr("value") && ["checkbox", "radio"].contains(type) ? "on" : control.attr("value")
                fields.append(URLQueryItem(name: name, value: value))
            default:
                fields.append(URLQueryItem(name: name, value: try control.val()))
            }
        }
        func options(_ name: String) throws -> [TimetableCaptureOption] {
            guard let select = try form.select("select[name=\(name)]").first() else { throw TimetableCaptureError.unsupportedForm }
            return try select.select("option").array().filter { !$0.hasAttr("disabled") }.map {
                TimetableCaptureOption(value: try $0.hasAttr("value") ? $0.attr("value") : $0.text(), title: try $0.text())
            }
        }
        let cells = try document.select("#kbtable .kbcontent:not(.sykb2)").array()
        let texts = try cells.map { try $0.text() }
        return Self(
            actionURL: url, fields: fields,
            terms: try options("xnxq01id"), weeks: try options("zc"), templates: try options("kbjcmsid"),
            detailedCellCount: cells.count,
            occupiedCellCount: texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
            gridDigest: SHA256.hash(data: Data(texts.joined(separator: "\u{1f}").utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    func makeRequest(selection: TimetableCaptureSelection, cookie: String) throws -> URLRequest {
        guard terms.contains(where: { $0.value == selection.termID }),
              weeks.contains(where: { $0.value == selection.week }),
              templates.contains(where: { $0.value == selection.templateID }) else {
            throw TimetableCaptureError.invalidSelection
        }
        let overrides = ["xnxq01id": selection.termID, "zc": selection.week, "kbjcmsid": selection.templateID]
        var items = fields.filter { overrides[$0.name] == nil }
        for name in ["xnxq01id", "zc", "kbjcmsid"] { items.append(URLQueryItem(name: name, value: overrides[name])) }
        var form = URLComponents()
        form.queryItems = items
        guard let encoded = form.percentEncodedQuery else { throw TimetableCaptureError.unsupportedForm }
        var request = URLRequest(url: actionURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(actionURL.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = Data(encoded.replacingOccurrences(of: "+", with: "%2B").utf8)
        return request
    }

    func reflects(_ selection: TimetableCaptureSelection) -> Bool {
        selectedTermID == selection.termID && selectedWeek == selection.week && selectedTemplateID == selection.templateID
    }

    var summary: [String: Any] {
        ["academicTermOptionCount": terms.count, "weekOptionCount": weeks.count,
         "templateOptionCount": templates.count, "detailedCellCount": detailedCellCount,
         "occupiedCellCount": occupiedCellCount, "gridSHA256": gridDigest,
         "selectedTermID": selectedTermID ?? "", "selectedWeek": selectedWeek ?? "",
         "selectedTemplateID": selectedTemplateID ?? ""]
    }
}
