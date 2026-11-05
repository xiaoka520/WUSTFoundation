import Foundation
import SwiftSoup

struct GradeForm: Sendable {
    let options: GradeQueryOptions
    let fields: [URLQueryItem]
}

struct GradeFormParser {
    func parse(from html: String) throws -> GradeForm {
        let document = try SwiftSoup.parse(html)
        guard let form = try document.getElementById("kscjQueryForm") else { throw GradeError.formNotFound }
        guard form.tagName() == "form", try form.attr("method").lowercased() == "post" else {
            throw GradeError.unsupportedForm
        }
        let action = try form.attr("action").trimmingCharacters(in: .whitespacesAndNewlines)
        guard action.isEmpty || action == "/jsxsd/kscj/cjcx_list" else { throw GradeError.unsupportedForm }
        if action.isEmpty {
            let scripts = try document.select("script").array().map { try $0.html() }.joined(separator: "\n")
            guard scripts.range(
                of: #"document\.forms\s*\[\s*["']kscjQueryForm["']\s*\]\s*\.action\s*=\s*["']/jsxsd/kscj/cjcx_list["']"#,
                options: .regularExpression
            ) != nil else { throw GradeError.unsupportedForm }
        }
        for name in ["kksj", "kcxz", "kcmc", "xsfs", "sfxsbcxq"] {
            let controls = try form.select("[name=\(name)]").array()
            guard controls.count == 1, let control = controls.first, !control.hasAttr("disabled") else {
                throw GradeError.unsupportedForm
            }
        }
        let options = try GradeQueryOptions(
            terms: readOptions("kksj", in: form),
            courseNatures: readOptions("kcxz", in: form),
            displayModes: readOptions("xsfs", in: form)
        )
        guard let checkbox = try form.select("input[name=sfxsbcxq]").first(),
              try checkbox.attr("type").lowercased() == "checkbox", try checkbox.attr("value") == "1" else {
            throw GradeError.unsupportedForm
        }
        var fields: [URLQueryItem] = []
        for control in try form.select("input, select, textarea") {
            let name = try control.attr("name")
            if name.isEmpty || control.hasAttr("disabled") { continue }
            switch control.tagName() {
            case "input":
                let type = try control.attr("type").lowercased()
                if ["button", "submit", "reset", "image", "file"].contains(type) { continue }
                if ["radio", "checkbox"].contains(type), !control.hasAttr("checked") { continue }
                fields.append(URLQueryItem(name: name, value: try control.attr("value")))
            case "select":
                let available = try control.select("option").array().filter { !$0.hasAttr("disabled") }
                let selected = available.filter { $0.hasAttr("selected") }
                let chosen = selected.isEmpty ? Array(available.prefix(1)) : selected
                guard !control.hasAttr("multiple"), chosen.count == 1, let option = chosen.first else {
                    throw GradeError.unsupportedForm
                }
                fields.append(URLQueryItem(name: name, value: try option.attr("value")))
            case "textarea":
                fields.append(URLQueryItem(name: name, value: try control.val()))
            default: break
            }
        }
        return GradeForm(options: options, fields: fields)
    }

    private func readOptions(_ name: String, in form: Element) throws -> [GradeOption] {
        guard let select = try form.select("select[name=\(name)]").first(), !select.hasAttr("multiple") else {
            throw GradeError.unsupportedForm
        }
        let elements = try select.select("option").array().filter { !$0.hasAttr("disabled") }
        var result: [GradeOption] = []
        var seen = Set<String>()
        for element in elements {
            guard element.hasAttr("value") else { throw GradeError.unsupportedForm }
            let id = try element.attr("value")
            let name = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert(id).inserted, !name.isEmpty else { throw GradeError.unsupportedForm }
            result.append(GradeOption(id: id, name: name))
        }
        guard !result.isEmpty else { throw GradeError.unsupportedForm }
        return result
    }
}
