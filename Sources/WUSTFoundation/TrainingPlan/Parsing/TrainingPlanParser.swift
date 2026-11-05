import Foundation
import SwiftSoup

public struct TrainingPlanParser: Sendable {
    public init() {}

    public func parse(from html: String) throws -> TrainingPlan {
        let document = try SwiftSoup.parse(html)
        guard let root = try document.getElementById("dataList"),
              let courses = try root.select("table#mxh").first() else {
            throw TrainingPlanError.planNotFound
        }
        guard let caption = root.children().array().first(where: { $0.tagName() == "caption" }) else {
            throw TrainingPlanError.titleNotFound
        }
        let title = try caption.text().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TrainingPlanError.titleNotFound }
        let headers = try courses.select("th").array().map { try $0.text() }
        guard ["课程编号", "课程名称", "学分", "开设学期"].allSatisfy(headers.contains) else {
            throw TrainingPlanError.invalidTableStructure
        }
        let nodes = root.getChildNodes().filter { $0 !== caption }
        let blocks = try TrainingPlanContentParser().parse(nodes, depth: 0)
        guard !blocks.isEmpty else { throw TrainingPlanError.planNotFound }
        return TrainingPlan(title: title, blocks: blocks)
    }
}
