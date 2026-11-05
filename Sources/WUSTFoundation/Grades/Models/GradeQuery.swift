public enum GradeDisplayMode: String, Codable, Hashable, Sendable {
    case all = "all"
    case best = "max"
}

public struct GradeQuery: Codable, Hashable, Sendable {
    public let termID: String?
    public let courseNatureID: String?
    public let courseName: String
    public let displayMode: GradeDisplayMode
    public let includesRetakes: Bool

    public init(
        termID: String? = nil,
        courseNatureID: String? = nil,
        courseName: String = "",
        displayMode: GradeDisplayMode = .all,
        includesRetakes: Bool = false
    ) {
        self.termID = termID
        self.courseNatureID = courseNatureID
        self.courseName = courseName
        self.displayMode = displayMode
        self.includesRetakes = includesRetakes
    }
}

public struct GradeOption: Codable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct GradeQueryOptions: Codable, Hashable, Sendable {
    public let terms: [GradeOption]
    public let courseNatures: [GradeOption]
    public let displayModes: [GradeOption]

    public init(terms: [GradeOption], courseNatures: [GradeOption], displayModes: [GradeOption]) {
        self.terms = terms
        self.courseNatures = courseNatures
        self.displayModes = displayModes
    }
}
