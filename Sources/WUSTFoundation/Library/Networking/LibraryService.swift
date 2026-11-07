import Foundation

public struct LibraryService: Sendable {
    private let pageSize: Int

    public init(pageSize: Int = 100) {
        self.pageSize = min(max(pageSize, 1), 100)
    }

    public func fetchDashboard(
        credential: UnionCredential,
        using session: URLSession
    ) async throws -> LibraryDashboard {
        try await withLibraryCookie(credential: credential, using: session) { cookie in
            let statistics = try await fetchStatistics(cookie: cookie, using: session)
            let currentLoans = try await fetchCurrentLoans(cookie: cookie, using: session)
            let overdueSoon = try await fetchOverdueSoon(cookie: cookie, using: session)
            return LibraryDashboard(
                statistics: statistics,
                currentLoans: currentLoans,
                overdueSoon: overdueSoon
            )
        }
    }

    public func fetchStatistics(cookie: String, using session: URLSession) async throws -> LibraryStatistics {
        let request = try LibraryRequestFactory().makeStatisticsRequest(cookie: cookie)
        let payload = try await fetchPayload(request, using: session)
        return try LibraryStatistics(fields: record(from: payload))
    }

    public func fetchCurrentLoans(
        cookie: String,
        page: Int = 1,
        pageSize: Int? = nil,
        using session: URLSession
    ) async throws -> LibraryPage<LibraryLoan> {
        let size = pageSize ?? self.pageSize
        let request = try LibraryRequestFactory().makeCurrentLoansRequest(cookie: cookie, page: page, pageSize: size)
        return try await fetchPage(
            request, requestedPage: page, requestedSize: size, using: session
        )
    }

    public func fetchOverdueSoon(
        cookie: String,
        page: Int = 1,
        pageSize: Int? = nil,
        using session: URLSession
    ) async throws -> LibraryPage<LibraryLoan> {
        let size = pageSize ?? self.pageSize
        let request = try LibraryRequestFactory().makeOverdueSoonRequest(cookie: cookie, page: page, pageSize: size)
        return try await fetchPage(
            request, requestedPage: page, requestedSize: size, using: session
        )
    }

    public func fetchRequests(
        cookie: String, page: Int = 1, pageSize: Int = 5, using session: URLSession
    ) async throws -> LibraryPage<LibraryRecord> {
        let request = try LibraryRequestFactory().makeRequestsRequest(cookie: cookie, page: page, pageSize: pageSize)
        return try await fetchRecords(request, using: session)
    }

    public func fetchFines(
        cookie: String, page: Int = 1, pageSize: Int = 10, using session: URLSession
    ) async throws -> LibraryPage<LibraryRecord> {
        let request = try LibraryRequestFactory().makeFinesRequest(cookie: cookie, page: page, pageSize: pageSize)
        return try await fetchRecords(request, using: session)
    }

    public func fetchBooklists(cookie: String, using session: URLSession) async throws -> [LibraryBooklist] {
        let request = try LibraryRequestFactory().makeBooklistsRequest(cookie: cookie)
        let payload = try await fetchPayload(request, using: session)
        guard case .array(let items) = payload else { throw LibraryError.invalidPayload }
        return try items.map { try LibraryBooklist(fields: record(from: $0)) }
    }

    public func fetchBooklistInfo(
        id: String, cookie: String, using session: URLSession
    ) async throws -> LibraryBooklist {
        let request = try LibraryRequestFactory().makeBooklistInfoRequest(id: id, cookie: cookie)
        let payload = try await fetchPayload(request, using: session)
        return try LibraryBooklist(fields: record(from: payload))
    }

    public func fetchBooklistBooks(
        id: String, cookie: String, page: Int = 1, pageSize: Int = 10, using session: URLSession
    ) async throws -> LibraryPage<LibraryRecord> {
        let request = try LibraryRequestFactory().makeBooklistBooksRequest(
            id: id, cookie: cookie, page: page, pageSize: pageSize
        )
        return try await fetchRecords(request, using: session)
    }

    func withLibraryCookie<Value: Sendable>(
        credential: UnionCredential,
        using session: URLSession,
        perform query: @Sendable (String) async throws -> Value
    ) async throws -> Value {
        let factory = LibraryRequestFactory()
        let url = try factory.statisticsURL()
        if let cookie = readCookie(for: url, using: session) {
            do {
                return try await query(cookie)
            } catch LibraryError.authenticationRequired {
            }
        }

        let ticket = try await UnionAuthService().fetchServiceTicket(
            credential: credential,
            service: factory.libraryServiceURL(),
            using: session
        )
        let ticketRequest = try factory.makeTicketExchangeRequest(ticket: ticket)
        _ = try await LibraryPageLoader().fetch(ticketRequest, using: session, followsRedirects: true)
        let indexRequest = try factory.makeIndexRequest()
        _ = try await LibraryPageLoader().fetch(indexRequest, using: session, followsRedirects: true)
        guard let cookie = readCookie(for: url, using: session) else {
            throw LibraryError.authenticationRequired
        }
        return try await query(cookie)
    }

    private func fetchRecords(
        _ request: URLRequest, using session: URLSession
    ) async throws -> LibraryPage<LibraryRecord> {
        let payload = try await fetchPayload(request, using: session)
        let fields = try record(from: payload)
        guard let currentPage = fields["currentPage"]?.integerValue, currentPage >= 1,
              let size = fields["pageSize"]?.integerValue, size >= 1,
              let totalPages = fields["totalPage"]?.integerValue, totalPages >= 0,
              let totalItems = fields["total"]?.integerValue, totalItems >= 0,
              case .array(let items)? = fields["items"] else {
            throw LibraryError.invalidPayload
        }
        return try LibraryPage(
            currentPage: currentPage,
            pageSize: size,
            totalPages: totalPages,
            totalItems: totalItems,
            items: items.map { try record(from: $0) }
        )
    }

    private func fetchPage(
        _ request: URLRequest,
        requestedPage: Int,
        requestedSize: Int,
        using session: URLSession
    ) async throws -> LibraryPage<LibraryLoan> {
        let payload = try await fetchPayload(request, using: session)
        let pageObject: LibraryRecord
        let itemValues: [LibraryJSONValue]
        switch payload {
        case .array(let values):
            pageObject = [:]
            itemValues = values
        case .object(let fields):
            pageObject = fields
            guard case .array(let items)? = fields["items"] else {
                throw LibraryError.invalidPayload
            }
            itemValues = items
        default:
            throw LibraryError.invalidPayload
        }
        let items = try itemValues.map { try decodeLoan(record(from: $0)) }
        return LibraryPage(
            currentPage: pageObject["currentPage"]?.integerValue ?? requestedPage,
            pageSize: pageObject["pageSize"]?.integerValue ?? requestedSize,
            totalPages: pageObject["totalPage"]?.integerValue ?? (items.isEmpty ? 0 : 1),
            totalItems: pageObject["total"]?.integerValue ?? items.count,
            items: items
        )
    }

    private func fetchPayload(_ request: URLRequest, using session: URLSession) async throws -> LibraryJSONValue {
        let data = try await LibraryPageLoader().fetch(request, using: session)
        let json: LibraryJSONValue
        do {
            json = try JSONDecoder().decode(LibraryJSONValue.self, from: data)
        } catch {
            throw LibraryError.invalidPayload
        }
        guard case .object(let root) = json else { return json }
        if let value = root["code"] {
            guard let code = value.integerValue else { throw LibraryError.invalidPayload }
            guard code == 0 || code == 200 else { throw LibraryError.serviceRejected(code) }
            guard let payload = root["data"] else { throw LibraryError.invalidPayload }
            return payload
        }
        return root["data"] ?? json
    }

    private func record(from value: LibraryJSONValue) throws -> LibraryRecord {
        guard case .object(let fields) = value else { throw LibraryError.invalidPayload }
        return fields
    }

    private func decodeLoan(_ fields: LibraryRecord) throws -> LibraryLoan {
        do {
            return try JSONDecoder().decode(LibraryLoan.self, from: JSONEncoder().encode(fields))
        } catch {
            throw LibraryError.invalidPayload
        }
    }

    private func readCookie(for url: URL, using session: URLSession) -> String? {
        let cookies = session.configuration.httpCookieStorage?.cookies(for: url) ?? []
        guard let cookie = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], !cookie.isEmpty else {
            return nil
        }
        return cookie
    }
}
