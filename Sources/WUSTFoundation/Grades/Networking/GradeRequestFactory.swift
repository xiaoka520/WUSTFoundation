import Foundation

struct GradeRequestFactory {
    func makeEntryRequest(cookie: String) throws -> URLRequest {
        var request = URLRequest(url: try url(path: "/jsxsd/kscj/cjcx_query"))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        return request
    }

    func makeQueryRequest(query: GradeQuery, form: GradeForm, cookie: String) throws -> URLRequest {
        let termID = query.termID ?? ""
        let natureID = query.courseNatureID ?? ""
        guard form.options.terms.contains(where: { $0.id == termID }),
              form.options.courseNatures.contains(where: { $0.id == natureID }),
              form.options.displayModes.contains(where: { $0.id == query.displayMode.rawValue }) else {
            throw GradeError.invalidQuery
        }
        let names = Set(["kksj", "kcxz", "kcmc", "xsfs", "sfxsbcxq"])
        var fields = form.fields.filter { !names.contains($0.name) }
        fields += [
            URLQueryItem(name: "kksj", value: termID),
            URLQueryItem(name: "kcxz", value: natureID),
            URLQueryItem(name: "kcmc", value: query.courseName),
            URLQueryItem(name: "xsfs", value: query.displayMode.rawValue)
        ]
        if query.includesRetakes { fields.append(URLQueryItem(name: "sfxsbcxq", value: "1")) }
        var components = URLComponents()
        components.queryItems = fields
        guard let encoded = components.percentEncodedQuery else { throw GradeError.invalidFormEncoding }
        var request = URLRequest(url: try url(path: "/jsxsd/kscj/cjcx_list"))
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(try url(path: "/jsxsd/kscj/cjcx_query").absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = Data(encoded.replacingOccurrences(of: "+", with: "%2B").utf8)
        return request
    }

    func listURL() throws -> URL {
        try url(path: "/jsxsd/kscj/cjcx_list")
    }

    private func url(path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "bkjx.wust.edu.cn"
        components.path = path
        guard let url = components.url else { throw GradeError.invalidURL }
        return url
    }
}
