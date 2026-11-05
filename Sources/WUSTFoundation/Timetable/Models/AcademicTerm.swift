public struct AcademicTerm: Codable, Hashable, Sendable {
    public let id: String
    public let name: String


    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct AcademicTermList: Codable, Hashable, Sendable {
    public let terms: [AcademicTerm]
    public let selectedTermID: String?

    public init(terms: [AcademicTerm], selectedTermID: String? = nil) {
        self.terms = terms
        self.selectedTermID = selectedTermID
    }
}
