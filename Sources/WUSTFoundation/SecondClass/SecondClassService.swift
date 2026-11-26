import Foundation

public struct SecondClassService: Sendable {
    private static let baseURL = URL(string: "https://xg.wust.edu.cn/xsfw/sys/dektapp/")!
    private static let entryURL = baseURL.appendingPathComponent("*default/index.do")

    public init() {}

    public func fetchTranscript(
        credential: UnionCredential, using session: URLSession
    ) async throws -> SecondClassTranscript {
        do {
            return try await fetchTranscript(using: session)
        } catch SecondClassError.authenticationRequired {
            let ticket = try await UnionAuthService().fetchServiceTicket(
                credential: credential, service: Self.entryURL.absoluteString, using: session
            )
            var components = URLComponents(url: Self.entryURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
            let request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
            let (_, response) = try await session.data(for: request, delegate: SecondClassRedirectDelegate())
            guard let http = response as? HTTPURLResponse, let url = http.url else {
                throw SecondClassError.invalidResponse
            }
            guard Self.isStudentAffairsURL(url) else { throw SecondClassError.unexpectedRedirect }
            if (300..<400).contains(http.statusCode) || http.statusCode == 401 {
                throw SecondClassError.ticketExchangeRejected(http.statusCode)
            }
            guard http.statusCode == 200 else { throw SecondClassError.unexpectedStatusCode(http.statusCode) }
            return try await fetchTranscript(using: session)
        }
    }

    public func fetchTranscript(using session: URLSession) async throws -> SecondClassTranscript {
        try await initializeApplication(using: session)
        let grades: SecondClassGrades = try await fetch("getCj.do", using: session)
        let summary: SecondClassSummary = try await fetch("getSzfzpj.do", using: session)
        return SecondClassTranscript(
            categories: grades.cj.compactMap(\.category),
            earnedCredits: summary.ZXF.value,
            evaluation: summary.PJ
        )
    }

    private func initializeApplication(using session: URLSession) async throws {
        var components = URLComponents(
            string: "https://xg.wust.edu.cn/xsfw/sys/swpubapp/indexmenu/getAppConfig.do"
        )!
        components.queryItems = [
            URLQueryItem(name: "appId", value: "5446046383738452"),
            URLQueryItem(name: "appName", value: "dektapp")
        ]
        let data = try await fetchData(makeRequest(url: components.url!), using: session)
        guard let configuration = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              configuration["MODULES"] != nil else {
            throw SecondClassError.invalidResponse
        }
    }

    private func fetch<Value: Decodable>(_ action: String, using session: URLSession) async throws -> Value {
        let url = Self.baseURL.appendingPathComponent("modules/cjdcxManage/" + action)
        let data = try await fetchData(makeRequest(url: url), using: session)
        do {
            return try JSONDecoder().decode(SecondClassResponse<Value>.self, from: data).data
        } catch let error as SecondClassError {
            throw error
        } catch {
            throw SecondClassError.invalidResponse
        }
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.httpBody = Data()
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(Self.entryURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("https://xg.wust.edu.cn", forHTTPHeaderField: "Origin")
        return request
    }

    private func fetchData(_ request: URLRequest, using session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(
            for: request, delegate: SecondClassRedirectDelegate(followsRedirects: false)
        )
        guard let http = response as? HTTPURLResponse, let finalURL = http.url else {
            throw SecondClassError.invalidResponse
        }
        if http.statusCode == 401 || (300..<400).contains(http.statusCode) || http.mimeType == "text/html" {
            throw SecondClassError.authenticationRequired
        }
        guard http.statusCode == 200 else { throw SecondClassError.unexpectedStatusCode(http.statusCode) }
        guard Self.isStudentAffairsURL(finalURL), finalURL.path == request.url?.path else {
            throw SecondClassError.unexpectedRedirect
        }
        return data
    }

    fileprivate static func isStudentAffairsURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "xg.wust.edu.cn" && (url.port ?? 443) == 443 &&
            url.user == nil && url.password == nil
    }
}

private final class SecondClassRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let followsRedirects: Bool

    init(followsRedirects: Bool = true) { self.followsRedirects = followsRedirects }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard followsRedirects, let url = request.url, SecondClassService.isStudentAffairsURL(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

struct SecondClassResponse<Value: Decodable>: Decodable {
    let data: Value

    private enum CodingKeys: String, CodingKey { case code, data }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code: String
        if let text = try? container.decode(String.self, forKey: .code) {
            code = text
        } else {
            code = String(try container.decode(Int.self, forKey: .code))
        }
        guard code == "0" else { throw SecondClassError.rejected(code) }
        data = try container.decode(Value.self, forKey: .data)
    }
}

struct SecondClassGrades: Decodable {
    let cj: [SecondClassGrade]
}

struct SecondClassGrade: Decodable {
    let MKDM: String
    let NR: String
    let XF: SecondClassNumber
    let YXXF: SecondClassNumber
    let BXXF: SecondClassNumber
    let XXXF: SecondClassNumber
    let bxyxxf: SecondClassNumber
    let xxyxxfR: SecondClassNumber

    var category: SecondClassCreditCategory? {
        let requirements = [
            SecondClassCreditRequirement(kind: .required, requiredCredits: BXXF.value, earnedCredits: bxyxxf.value),
            SecondClassCreditRequirement(kind: .elective, requiredCredits: XXXF.value, earnedCredits: xxyxxfR.value)
        ].filter { $0.requiredCredits > 0 }
        guard !requirements.isEmpty else { return nil }
        return SecondClassCreditCategory(
            id: MKDM, name: NR, requiredCredits: XF.value, earnedCredits: YXXF.value, requirements: requirements
        )
    }
}

private struct SecondClassSummary: Decodable {
    let ZXF: SecondClassNumber
    let PJ: String
}

struct SecondClassNumber: Decodable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            guard let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
                  text.range(of: #"\A[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil else {
                throw SecondClassError.invalidResponse
            }
            value = number
        } else {
            value = try container.decode(Decimal.self)
        }
        guard !value.isNaN, value >= 0 else { throw SecondClassError.invalidResponse }
    }
}
