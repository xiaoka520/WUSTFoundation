public struct GradeField: Codable, Hashable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct GradeRecord: Codable, Hashable, Sendable {
    public let fields: [GradeField]

    public init(fields: [GradeField]) {
        self.fields = fields
    }

    public var termID: String { value(for: "开课学期") ?? "" }
    public var courseID: String { value(for: "课程编号") ?? "" }
    public var courseName: String { value(for: "课程名称") ?? "" }
    public var score: String { value(for: "成绩") ?? "" }
    public var groupName: String? { value(for: "分组名") }
    public var scoreFlag: String? { value(for: "成绩标识") }
    public var credits: String? { value(for: "学分") }
    public var totalHours: String? { value(for: "总学时") }
    public var gradePoint: String? { value(for: "绩点") }
    public var retakeTermID: String? { value(for: "补重学期") }
    public var assessmentMethod: String? { value(for: "考核方式") }
    public var examType: String? { value(for: "考试性质") }
    public var courseNature: String? { value(for: "课程性质") }
    public var generalElectiveCategory: String? { value(for: "通选课类别") }

    public func value(for fieldName: String) -> String? {
        fields.first { $0.name == fieldName }?.value
    }
}

public struct GradeReport: Codable, Hashable, Sendable {
    public let query: GradeQuery
    public let columns: [String]
    public let records: [GradeRecord]

    public init(query: GradeQuery, columns: [String], records: [GradeRecord]) {
        self.query = query
        self.columns = columns
        self.records = records
    }
}
