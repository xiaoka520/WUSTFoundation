import Foundation
import ImageIO

public enum StudentAvatarError: Error, Equatable, Sendable {
    case authenticationRequired
    case invalidResponse
    case unexpectedStatusCode(Int)
    case rejected(String)
    case imageTooLarge
    case invalidImage
}

public struct StudentAvatarService: Sendable {
    private static let pageURL = URL(string: "https://auth.wust.edu.cn/personalInfo/personCenter/index.html")!
    private static let maximumImageBytes = 8 * 1024 * 1024

    public init() {}

    public func fetchAvatar(using session: URLSession) async throws -> Data? {
        var pageRequest = URLRequest(url: Self.pageURL)
        pageRequest.cachePolicy = .reloadIgnoringLocalCacheData
        pageRequest.timeoutInterval = 30
        let (_, pageResponse) = try await session.data(for: pageRequest, delegate: AvatarRedirectPolicy())
        try Task.checkCancellation()
        let pageHTTP = try Self.response(pageResponse)
        guard pageHTTP.url?.path == Self.pageURL.path else {
            throw StudentAvatarError.authenticationRequired
        }

        var components = URLComponents(string: "https://auth.wust.edu.cn/personalInfo/UserData/user/queryUserData")!
        components.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
        let url = components.url!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(Self.pageURL.absoluteString, forHTTPHeaderField: "Referer")
        if let token = session.configuration.httpCookieStorage?.cookies(for: url)?
            .first(where: { $0.name == "REFERERCE_TOKEN" })?.value {
            request.setValue(token, forHTTPHeaderField: "refererToken")
        }
        let (data, response) = try await session.data(for: request, delegate: AvatarRedirectPolicy())
        try Task.checkCancellation()
        let http = try Self.response(response)
        guard http.url?.path == url.path else { throw StudentAvatarError.authenticationRequired }
        guard data.count <= 12 * 1024 * 1024 else { throw StudentAvatarError.imageTooLarge }
        guard http.mimeType?.lowercased() == "application/json" else {
            throw StudentAvatarError.invalidResponse
        }
        return try Self.avatar(from: data)
    }

    static func avatar(from response: Data) throws -> Data? {
        let result = try JSONDecoder().decode(AvatarResponse.self, from: response)
        if result.code == "2106040302" { throw StudentAvatarError.authenticationRequired }
        guard result.code == "0" else { throw StudentAvatarError.rejected(result.code) }
        guard let fields = result.datas else { throw StudentAvatarError.invalidResponse }
        guard var encoded = fields.headImageIcon, !encoded.isEmpty else { return nil }
        if encoded.hasPrefix("data:") {
            guard let comma = encoded.firstIndex(of: ","),
                  encoded[..<comma].hasPrefix("data:image/"),
                  encoded[..<comma].hasSuffix(";base64") else { throw StudentAvatarError.invalidImage }
            encoded = String(encoded[encoded.index(after: comma)...])
        }
        guard encoded.utf8.count <= ((maximumImageBytes + 2) / 3) * 4 else {
            throw StudentAvatarError.imageTooLarge
        }
        guard let data = Data(base64Encoded: encoded),
              let image = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(image) > 0 else { throw StudentAvatarError.invalidImage }
        guard data.count <= maximumImageBytes else { throw StudentAvatarError.imageTooLarge }
        return data
    }

    private static func response(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse, let url = http.url else {
            throw StudentAvatarError.invalidResponse
        }
        guard url.scheme == "https", url.host == "auth.wust.edu.cn",
              url.port == nil || url.port == 443 else { throw StudentAvatarError.authenticationRequired }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw StudentAvatarError.authenticationRequired
        }
        guard http.statusCode == 200 else { throw StudentAvatarError.unexpectedStatusCode(http.statusCode) }
        return http
    }
}

private struct AvatarResponse: Decodable {
    let code: String
    let datas: AvatarFields?
}

private struct AvatarFields: Decodable {
    let headImageIcon: String?
}

private final class AvatarRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let url = request.url
        let allowed = url?.scheme == "https" && url?.host == "auth.wust.edu.cn"
            && (url?.port == nil || url?.port == 443)
        completionHandler(allowed ? request : nil)
    }
}
