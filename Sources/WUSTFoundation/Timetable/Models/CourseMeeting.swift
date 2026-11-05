public enum Weekday: Int, Codable, Hashable, Sendable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7
}

public struct CourseMeeting: Codable, Hashable, Sendable {
    public let courseID: String?
    public let name: String
    public let teacher: String?
    public let teachingClass: String?
    public let location: String?
    public let weekday: Weekday
    public let weeks: [Int]
    public let sections: [Int]

    public init(
        name: String,
        weekday: Weekday,
        weeks: [Int],
        sections: [Int],
        courseID: String? = nil,
        teacher: String? = nil,
        teachingClass: String? = nil,
        location: String? = nil
    ) {
        self.name = name
        self.weekday = weekday
        self.weeks = weeks
        self.sections = sections
        self.courseID = courseID
        self.teacher = teacher
        self.teachingClass = teachingClass
        self.location = location
    }
}
