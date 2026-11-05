public struct ExamQuery: Codable, Hashable, Sendable {
    public let termID: String
    public let categoryID: String?

    public init(termID: String, categoryID: String? = nil) {
        self.termID = termID
        self.categoryID = categoryID
    }
}

public struct ExamOption: Codable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ExamQueryOptions: Codable, Hashable, Sendable {
    public let terms: [ExamOption]
    public let categories: [ExamOption]
    public let selectedTermID: String?
    public let selectedCategoryID: String?

    public init(
        terms: [ExamOption],
        categories: [ExamOption],
        selectedTermID: String?,
        selectedCategoryID: String?
    ) {
        self.terms = terms
        self.categories = categories
        self.selectedTermID = selectedTermID
        self.selectedCategoryID = selectedCategoryID
    }
}
