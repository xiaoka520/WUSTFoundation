import Foundation

public enum ExamArrangementSource: String, Codable, Hashable, Sendable {
    case centralized
    case selfRequested

    public var name: String {
        switch self {
        case .centralized: return "统一安排考试"
        case .selfRequested: return "自主申请考试"
        }
    }
}

public struct ExamField: Codable, Hashable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct ExamTimeRange: Codable, Hashable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var timeZoneIdentifier: String { "Asia/Shanghai" }
}

public struct ExamArrangement: Codable, Hashable, Sendable {
    public let source: ExamArrangementSource
    public let fields: [ExamField]
    public let timeRange: ExamTimeRange?

    public init(source: ExamArrangementSource, fields: [ExamField], timeRange: ExamTimeRange?) {
        self.source = source
        self.fields = fields
        self.timeRange = timeRange
    }

    public var termID: String { value(for: "学年学期") ?? "" }
    public var courseID: String { value(for: "课程编号") ?? "" }
    public var courseName: String { value(for: "课程名称") ?? "" }
    public var examSession: String? { value(for: "考试场次") }
    public var weekText: String? { value(for: "周次") }
    public var weekdayText: String? { value(for: "星期") }
    public var sectionText: String? { value(for: "节次") }
    public var timeText: String? { value(for: "时间") }
    public var seatNumber: String? { value(for: "座位号") }
    public var location: String? { value(for: "场地") }
    public var campus: String? { value(for: "校区") }

    public func value(for fieldName: String) -> String? {
        fields.first { $0.name == fieldName }?.value
    }
}

public struct ExamArrangementList: Codable, Hashable, Sendable {
    public let source: ExamArrangementSource
    public let columns: [String]
    public let arrangements: [ExamArrangement]

    public init(source: ExamArrangementSource, columns: [String], arrangements: [ExamArrangement]) {
        self.source = source
        self.columns = columns
        self.arrangements = arrangements
    }
}

public struct ExamSchedule: Codable, Hashable, Sendable {
    public let query: ExamQuery
    public let lists: [ExamArrangementList]

    public init(query: ExamQuery, lists: [ExamArrangementList]) {
        self.query = query
        self.lists = lists
    }

    public var arrangements: [ExamArrangement] { lists.flatMap(\.arrangements) }
}
