import Foundation
import SwiftSoup

enum NoticeTextExtractor {
    static func paragraphs(from element: Element) throws -> [String] {
        var text = ""
        try append(element, to: &text)
        return paragraphs(from: text)
    }

    static func paragraphs(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func append(_ node: Node, to output: inout String) throws {
        if let text = node as? TextNode {
            output += text.getWholeText().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return
        }
        guard let element = node as? Element else { return }
        let tag = element.tagName().lowercased()
        if ["script", "style", "noscript", "iframe", "svg", "canvas", "form", "input", "button", "object", "embed"].contains(tag) { return }
        if tag == "br" { output += "\n"; return }
        if tag == "tr" {
            let cells = element.children().array().filter { ["th", "td"].contains($0.tagName()) }
            output += "\n" + (try cells.map { try $0.text() }).joined(separator: "\t") + "\n"
            return
        }
        let isBlock = ["div", "p", "section", "article", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "table"].contains(tag)
        if isBlock { output += "\n" }
        for child in element.getChildNodes() { try append(child, to: &output) }
        if isBlock { output += "\n" }
    }
}
