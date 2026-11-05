import Foundation

struct TimetableRequestFactory {
    func makeEntryRequest(cookie: String) throws -> URLRequest {
        guard let url = URL(string: "https://bkjx.wust.edu.cn/jsxsd/xskb/xskb_list.do") else {
            throw TimetableError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        return request
    }

    func makeTimetableRequest(
        url: URL,
        fields: [URLQueryItem],
        termID: String,
        cookie: String
    ) throws -> URLRequest {
        var items = fields.filter { item in
            item.name != "xnxq01id" && item.name != "zc"
        }

        items.append(URLQueryItem(name: "xnxq01id", value: termID))
        items.append(URLQueryItem(name: "zc", value: ""))
        return try makeFormRequest(url: url, items: items, cookie: cookie, referer: url)
    }

    func makeTeachingCalendarRequest(date: AcademicDate, cookie: String) throws -> URLRequest {
        guard let url = URL(string: "https://bkjx.wust.edu.cn/jsxsd/framework/main_index_loadkb.jsp") else {
            throw TimetableError.invalidURL
        }
        return try makeFormRequest(
            url: url,
            items: [URLQueryItem(name: "rq", value: date.requestValue)],
            cookie: cookie,
            referer: nil
        )
    }

    private func makeFormRequest(
        url: URL,
        items: [URLQueryItem],
        cookie: String,
        referer: URL?
    ) throws -> URLRequest {
        var form = URLComponents()
        form.queryItems = items

        guard let query = form.percentEncodedQuery else {
            throw TimetableError.invalidFormEncoding
        }

        let body = query.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        request.httpBody = Data(body.utf8)
        return request
    }
}
