import Foundation
import SwiftSoup

struct TimetableForm: Sendable {
    let actionURL: URL
    let fields: [URLQueryItem]
}

struct TimetableFormParser {
    func parse(
        from html: String,
        sourceURL: URL
    ) throws -> TimetableForm {
        let document = try SwiftSoup.parse(html)
        guard let form = try document.select("form#Form1").first() else {
            throw TimetableError.formNotFound
        }
        let method = try form.attr("method").trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        guard method == "post" else {
            throw TimetableError.unsupportedForm
        }

        let action = try form.attr("action")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let actionURL: URL

        if action.isEmpty {
            actionURL = sourceURL
        } else {
            guard let url = URL(
                string: action,
                relativeTo: sourceURL
            )?.absoluteURL else {
                throw TimetableError.invalidURL
            }

            actionURL = url
        }

        guard actionURL.scheme == sourceURL.scheme,
              actionURL.host == sourceURL.host,
              actionURL.port == sourceURL.port,
              actionURL.path == sourceURL.path else {
            throw TimetableError.unsupportedForm
        }

        var fields: [URLQueryItem] = []

        for control in try form.select("input, select, textarea") {
            let name = try control.attr("name")

            if name.isEmpty || control.hasAttr("disabled") {
                continue
            }

            switch control.tagName() {
            case "input":
                let type = try control.attr("type").lowercased()
                if ["submit", "button", "reset", "file", "image"].contains(type) {
                    continue
                }

                let isChoice = ["checkbox", "radio"].contains(type)
                if isChoice && !control.hasAttr("checked") {
                    continue
                }

                let value: String
                if isChoice && !control.hasAttr("value") {
                    value = "on"
                } else {
                    value = try control.attr("value")
                }
                fields.append(URLQueryItem(name: name, value: value))
            case "select":
                let options = try control.select("option").array()
                    .filter { !$0.hasAttr("disabled") }
                let selected = options.filter { $0.hasAttr("selected") }

                let chosenOptions: [Element]
                if control.hasAttr("multiple") {
                    chosenOptions = selected
                } else if !selected.isEmpty {
                    chosenOptions = Array(selected.prefix(1))
                } else {
                    chosenOptions = Array(options.prefix(1))
                }

                for option in chosenOptions {
                    let value: String
                    if option.hasAttr("value") {
                        value = try option.attr("value")
                    } else {
                        value = try option.text()
                    }
                    fields.append(URLQueryItem(name: name, value: value))
                }
            case "textarea":
                fields.append(
                    URLQueryItem(name: name, value: try control.val())
                )
            default:
                continue
            }
        }

        return TimetableForm(
            actionURL: actionURL,
            fields: fields
        )
    }
}
