import Foundation

public struct LibraryLoan: Codable, Hashable, Sendable {
    public let bibID: String?
    public let title: String?
    public let author: String?
    public let loanDate: String?
    public let dueDate: String?
    public let location: String?
    public let barcode: String?
    public let attributes: LibraryBookAttributes?
    public let circulationStatus: LibraryJSONValue?
    public let status: LibraryJSONValue?
    public let temporaryLocation: LibraryJSONValue?
    public let callNumber: LibraryJSONValue?

    enum CodingKeys: String, CodingKey {
        case bibID = "bibId"
        case title, author, loanDate, dueDate, location
        case barcode = "barCode"
        case attributes = "bibAttrs"
        case circulationStatus = "circStatus"
        case status
        case temporaryLocation = "tempLocation"
        case callNumber = "callNo"
    }
}

public struct LibraryBookAttributes: Codable, Hashable, Sendable {
    public let isbn: String?
    public let publisher: String?
    public let publishYear: String?
    public let price: String?
    public let callNumber: String?
    public let classNumber: String?

    enum CodingKeys: String, CodingKey {
        case isbn, publisher, price
        case publishYear = "pub_year"
        case callNumber = "callno"
        case classNumber = "classno"
    }
}
