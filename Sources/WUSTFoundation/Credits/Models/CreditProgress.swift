import Foundation

public struct CreditProgress: Codable, Hashable, Sendable {
    public let courseCategories: [CreditCategoryProgress]
    public let generalElectives: [CreditCategoryProgress]
    public let pastSemesterStatistics: CreditSemesterStatistics?
    public let courses: [CreditCourseProgress]
}

public struct CreditCategoryProgress: Codable, Hashable, Sendable {
    public let name: String
    public let courseAttribute: String?
    public let requiredCredits: Decimal?
    public let earnedCredits: Decimal?

    public var remainingCredits: Decimal? {
        guard let requiredCredits, let earnedCredits else { return nil }
        return max(0, requiredCredits - earnedCredits)
    }
}

public struct CreditSemesterStatistics: Codable, Hashable, Sendable {
    public let semesterCount: Int?
    public let completedCourseCount: Int?
    public let completedCredits: Decimal?
    public let averageCreditsPerSemester: Decimal?
    public let failedCourseCount: Int?
    public let failedCredits: Decimal?
    public let unselectedCourseCount: Int?
    public let unselectedCredits: Decimal?
    public let requiredCourseCountWithoutCredits: Int?
    public let requiredCreditsNotEarned: Decimal?
}

public struct CreditCourseProgress: Codable, Hashable, Sendable {
    public let termID: String?
    public let courseID: String
    public let courseName: String
    public let credits: Decimal?
    public let courseNature: String?
    public let courseAttribute: String?
    public let status: String?
}
