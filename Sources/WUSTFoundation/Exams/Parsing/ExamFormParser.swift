import Foundation
import SwiftSoup

struct ExamForm: Sendable {
    let options: ExamQueryOptions
    let fields: [URLQueryItem]
}

struct ExamFormParser {
    func parse(from html: String) throws -> ExamForm {
        let document = try SwiftSoup.parse(html)
        guard let form = try document.getElementById("ksapQueryForm") else { throw ExamError.formNotFound }
        guard form.tagName() == "form", try form.attr("method").lowercased() == "post" else {
            throw ExamError.unsupportedForm
        }
        let action = try form.attr("action").trimmingCharacters(in: .whitespacesAndNewlines)
        guard action.isEmpty || action == "/jsxsd/xsks/xsksap_list" else { throw ExamError.unsupportedForm }
        if action.isEmpty {
            let scripts = try document.select("script").array().map { try $0.html() }.joined(separator: "\n")
            guard scripts.range(
                of: #"document\.forms\s*\[\s*["']ksapQueryForm["']\s*\]\s*\.action\s*=\s*["']/jsxsd/xsks/xsksap_list["']"#,
                options: .regularExpression
            ) != nil else { throw ExamError.unsupportedForm }
        }
        let terms = try readOptions("xnxqid", in: form)
        let categories = try readOptions("xqlb", in: form)
        var fields: [URLQueryItem] = []
        for control in try form.select("input, select, textarea") {
            let name = try control.attr("name")
            if name.isEmpty || control.hasAttr("disabled") { continue }
            if control.tagName() == "input" {
                let type = try control.attr("type").lowercased()
                if ["button", "submit", "reset", "image"].contains(type) { continue }
                guard type == "hidden" else { throw ExamError.unsupportedForm }
                fields.append(URLQueryItem(name: name, value: try control.attr("value")))
            } else if control.tagName() == "select" {
                let available = try control.select("option").array().filter { !$0.hasAttr("disabled") }
                let selected = available.filter { $0.hasAttr("selected") }
                let chosen = selected.isEmpty ? Array(available.prefix(1)) : selected
                guard !control.hasAttr("multiple"), chosen.count == 1, let option = chosen.first else {
                    throw ExamError.unsupportedForm
                }
                fields.append(URLQueryItem(name: name, value: try option.attr("value")))
            } else {
                throw ExamError.unsupportedForm
            }
        }
        let labels = fields.filter { $0.name == "xqlbmc" }
        guard labels.count == 1 else { throw ExamError.unsupportedForm }
        return ExamForm(options: ExamQueryOptions(
            terms: terms.options,
            categories: categories.options,
            selectedTermID: terms.selectedID,
            selectedCategoryID: categories.selectedID
        ), fields: fields)
    }

    private func readOptions(_ name: String, in form: Element) throws -> (options: [ExamOption], selectedID: String?) {
        let controls = try form.select("[name=\(name)]").array()
        guard controls.count == 1, let select = controls.first, select.tagName() == "select",
              !select.hasAttr("disabled"), !select.hasAttr("multiple") else { throw ExamError.unsupportedForm }
        let elements = try select.select("option").array().filter { !$0.hasAttr("disabled") }
        var options: [ExamOption] = []
        var selected: [String] = []
        var seen = Set<String>()
        for element in elements {
            guard element.hasAttr("value") else { throw ExamError.unsupportedForm }
            let id = try element.attr("value")
            let name = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert(id).inserted, !name.isEmpty else { throw ExamError.unsupportedForm }
            options.append(ExamOption(id: id, name: name))
            if element.hasAttr("selected") { selected.append(id) }
        }
        guard !options.isEmpty, selected.count <= 1 else { throw ExamError.unsupportedForm }
        return (options, selected.first)
    }
}
