import Foundation
import SwiftSoup

struct TrainingPlanContentParser {
    func parse(_ nodes: [Node], depth: Int) throws -> [TrainingPlanBlock] {
        guard depth <= 16 else { throw TrainingPlanError.contentTooLarge }
        var blocks: [TrainingPlanBlock] = []
        var pending = ""
        for node in nodes {
            try append(node, depth: depth, pending: &pending, blocks: &blocks)
        }
        flush(&pending, into: &blocks)
        return blocks
    }

    private func append(
        _ node: Node,
        depth: Int,
        pending: inout String,
        blocks: inout [TrainingPlanBlock]
    ) throws {
        if let text = node as? TextNode {
            pending += text.getWholeText().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return
        }
        guard let element = node as? Element else { return }
        let tag = element.tagName().lowercased()
        if ["script", "style", "noscript", "iframe", "input", "button", "select", "textarea", "object", "embed"].contains(tag) { return }
        if tag == "table" {
            flush(&pending, into: &blocks)
            blocks.append(.table(value: try TrainingPlanTableParser().parse(element, depth: depth + 1)))
            return
        }
        if tag == "br" {
            flush(&pending, into: &blocks)
            return
        }
        if tag == "img" {
            pending += try element.attr("alt")
            return
        }
        let isBlock = ["p", "div", "section", "article", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "td", "th", "blockquote"].contains(tag)
        if isBlock { flush(&pending, into: &blocks) }
        for child in element.getChildNodes() {
            try append(child, depth: depth, pending: &pending, blocks: &blocks)
        }
        if isBlock { flush(&pending, into: &blocks) }
    }

    private func flush(_ pending: inout String, into blocks: inout [TrainingPlanBlock]) {
        let value = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { blocks.append(.paragraph(text: value)) }
        pending = ""
    }
}
