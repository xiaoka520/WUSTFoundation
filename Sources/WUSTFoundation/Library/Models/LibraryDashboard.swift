import Foundation

public struct LibraryStatistics: Codable, Hashable, Sendable {
    public let fields: [String: LibraryJSONValue]

    public subscript(_ key: String) -> LibraryJSONValue? { fields[key] }

    public func integer(for key: String) -> Int? {
        fields[key]?.integerValue
    }

    public var loanCount: Int? { integer(for: "loanCount") }
    public var expireCount: Int? { integer(for: "expireCount") }
    public var requestCount: Int? { integer(for: "requestCount") }
    public var booklistCount: Int? { integer(for: "booklistCount") }

    public var fineSum: Decimal? {
        switch fields["fineSum"] {
        case .integer(let value)?: return Decimal(value)
        case .number(let value)?: return Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX"))
        case .string(let value)?: return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        default: return nil
        }
    }
}

public typealias LibraryRecord = [String: LibraryJSONValue]

public struct LibraryBooklist: Codable, Hashable, Sendable {
    public let fields: LibraryRecord

    public var id: String? {
        switch fields["_id"] {
        case .string(let value)?: return value
        case .integer(let value)?: return String(value)
        default: return nil
        }
    }

    public var name: String? { fields["booklistName"]?.stringValue }
    public var coverURL: String? { fields["coverUrl"]?.stringValue }
    public var description: String? { fields["description"]?.stringValue }
    public var clickCount: Int? { fields["_clickCount"]?.integerValue }
    public var recordCount: Int? { fields["recordCount"]?.integerValue }
}

public struct LibraryPage<Item: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public let currentPage: Int
    public let pageSize: Int
    public let totalPages: Int
    public let totalItems: Int
    public let items: [Item]

    public init(currentPage: Int, pageSize: Int, totalPages: Int, totalItems: Int, items: [Item]) {
        self.currentPage = currentPage
        self.pageSize = pageSize
        self.totalPages = totalPages
        self.totalItems = totalItems
        self.items = items
    }
}

public struct LibraryDashboard: Sendable {
    public let statistics: LibraryStatistics
    public let currentLoans: LibraryPage<LibraryLoan>
    public let overdueSoon: LibraryPage<LibraryLoan>

    public init(
        statistics: LibraryStatistics,
        currentLoans: LibraryPage<LibraryLoan>,
        overdueSoon: LibraryPage<LibraryLoan>
    ) {
        self.statistics = statistics
        self.currentLoans = currentLoans
        self.overdueSoon = overdueSoon
    }
}
