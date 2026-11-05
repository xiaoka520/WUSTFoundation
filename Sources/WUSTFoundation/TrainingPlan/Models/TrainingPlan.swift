import Foundation

public struct TrainingPlan: Codable, Hashable, Sendable {
    public let title: String
    public let blocks: [TrainingPlanBlock]

    public init(title: String, blocks: [TrainingPlanBlock]) {
        self.title = title
        self.blocks = blocks
    }

    public var text: String {
        ([title] + blocks.map(\.text)).joined(separator: "\n\n")
    }
}

public indirect enum TrainingPlanBlock: Codable, Hashable, Sendable {
    case paragraph(text: String)
    case table(value: TrainingPlanTable)

    public var text: String {
        switch self {
        case .paragraph(let text): return text
        case .table(let table): return table.text
        }
    }
}
