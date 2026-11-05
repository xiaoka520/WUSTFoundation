import Foundation

struct ExamRequestFactory {
    func entryURL() throws -> URL { try url(path: "/jsxsd/xsks/xsksap_query") }
    func listURL() throws -> URL { try url(path: "/jsxsd/xsks/xsksap_list") }

    func makeEntryRequest(cookie: String) throws -> URLRequest {
        var request = URLRequest(url: try entryURL())
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        return request
    }

    func makeQueryRequest(query: ExamQuery, form: ExamForm, cookie: String) throws -> URLRequest {
        let categoryID = query.categoryID ?? ""
        guard !query.termID.isEmpty, form.options.terms.contains(where: { $0.id == query.termID }),
              let category = form.options.categories.first(where: { $0.id == categoryID }) else {
            throw ExamError.invalidQuery
        }
        let label = categoryID.isEmpty ? (form.fields.first { $0.name == "xqlbmc" }?.value ?? "") : category.name
        let names = Set(["xnxqid", "xqlb", "xqlbmc"])
        var fields = form.fields.filter { !names.contains($0.name) }
        fields += [
            URLQueryItem(name: "xnxqid", value: query.termID),
            URLQueryItem(name: "xqlb", value: categoryID),
            URLQueryItem(name: "xqlbmc", value: label)
        ]
        var components = URLComponents()
        components.queryItems = fields
        guard let encoded = components.percentEncodedQuery else { throw ExamError.invalidFormEncoding }
        var request = URLRequest(url: try listURL())
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(try entryURL().absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = Data(encoded.replacingOccurrences(of: "+", with: "%2B").utf8)
        return request
    }

    private func url(path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "bkjx.wust.edu.cn"
        components.path = path
        guard let url = components.url else { throw ExamError.invalidURL }
        return url
    }
}
