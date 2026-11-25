import Foundation

/// A consistent Safari-compatible HTTP profile; URLSession still owns transport and cookies.
enum AuthServerRequestHeaders {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    static func apply(to request: inout URLRequest, ajax: Bool, referer: URL? = nil) {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh-Hans;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(ajax ? "application/json, text/javascript, */*; q=0.01"
                             : "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")
        if ajax { request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With") }
        guard let url = request.url else { return }
        if let referer, referer.scheme == url.scheme, referer.host == url.host, referer.port == url.port {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        if request.httpMethod == "POST", let host = url.host, let scheme = url.scheme {
            let port = url.port.map { ":\($0)" } ?? ""
            request.setValue("\(scheme)://\(host)\(port)", forHTTPHeaderField: "Origin")
        }
        // Do not supply Host, Content-Length, Accept-Encoding or Cookie manually.
    }
}
