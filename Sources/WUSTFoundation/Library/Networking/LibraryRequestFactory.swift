import Foundation

struct LibraryRequestFactory {
    private let baseURL = "https://libsys.wust.edu.cn"
    private let service = "https://libsys.wust.edu.cn:443/meta-local/opac/cas/rosetta"
    private let statisticsPath = "/meta-local/opac/users/stats"

    func libraryServiceURL() -> String { service }

    func makeTicketExchangeRequest(ticket: String) throws -> URLRequest {
        var components = URLComponents(string: service)
        components?.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
        guard let url = components?.url else { throw LibraryError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    func makeIndexRequest() throws -> URLRequest {
        var request = URLRequest(url: try url(path: "/meta-local/opac/cas/rosetta"))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    func statisticsURL() throws -> URL { try url(path: statisticsPath) }

    func makeStatisticsRequest(cookie: String) throws -> URLRequest {
        try get(path: statisticsPath, cookie: cookie)
    }

    func makeCurrentLoansRequest(cookie: String, page: Int, pageSize: Int) throws -> URLRequest {
        try pagedGet(path: "/meta-local/opac/users/loans", cookie: cookie, page: page, pageSize: pageSize)
    }

    func makeOverdueSoonRequest(cookie: String, page: Int, pageSize: Int) throws -> URLRequest {
        try pagedGet(path: "/meta-local/opac/users/overdue_soon", cookie: cookie, page: page, pageSize: pageSize)
    }

    func makeRequestsRequest(cookie: String, page: Int, pageSize: Int) throws -> URLRequest {
        try pagedGet(
            path: "/meta-local/opac/users/requests/list",
            cookie: cookie, page: page, pageSize: pageSize,
            filters: [
                URLQueryItem(name: "requestFlagStatus", value: "all"),
                URLQueryItem(name: "processStatus", value: "0")
            ]
        )
    }

    func makeFinesRequest(cookie: String, page: Int, pageSize: Int) throws -> URLRequest {
        try pagedGet(path: "/meta-local/opac/users/fines", cookie: cookie, page: page, pageSize: pageSize)
    }

    func makeBooklistsRequest(cookie: String) throws -> URLRequest {
        try get(path: "/meta-local/opac/booklists/tree", cookie: cookie)
    }

    func makeBooklistInfoRequest(id: String, cookie: String) throws -> URLRequest {
        try get(path: booklistPath(id: id) + "/info", cookie: cookie)
    }

    func makeBooklistBooksRequest(id: String, cookie: String, page: Int, pageSize: Int) throws -> URLRequest {
        try validatePagination(page: page, pageSize: pageSize)
        var request = try get(path: booklistPath(id: id) + "/detls", cookie: cookie)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["page": page, "pageSize": pageSize])
        return request
    }

    private func booklistPath(id: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        guard !id.isEmpty, id != ".", id != "..",
              id.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw LibraryError.invalidBooklistID
        }
        return "/meta-local/opac/booklists/" + encoded
    }

    private func validatePagination(page: Int, pageSize: Int) throws {
        guard page >= 1, (1...100).contains(pageSize) else { throw LibraryError.invalidPagination }
    }

    private func pagedGet(
        path: String, cookie: String, page: Int, pageSize: Int, filters: [URLQueryItem] = []
    ) throws -> URLRequest {
        try validatePagination(page: page, pageSize: pageSize)
        var components = URLComponents(url: try url(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = filters + [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        guard let requestURL = components?.url else { throw LibraryError.invalidURL }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        return request
    }

    private func get(path: String, cookie: String) throws -> URLRequest {
        var request = URLRequest(url: try url(path: path))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        return request
    }

    private func url(path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else { throw LibraryError.invalidURL }
        return url
    }
}
