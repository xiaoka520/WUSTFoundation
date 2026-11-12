import Foundation
import Testing
@testable import WUSTFoundation

struct SecondClassTests {
    @Test func initializesApplicationBeforeReadingTranscript() async throws {
        SecondClassProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SecondClassProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transcript = try await SecondClassService().fetchTranscript(using: session)
        #expect(transcript.categories.isEmpty)
        #expect(transcript.earnedCredits == 0)
        #expect(transcript.evaluation == "测试评价")
    }

    @Test func filtersRequirementsWithoutCreditsAndUsesDisplayedElectiveScore() throws {
        let data = Data(#"""
        {"code":"0","data":{"cj":[
          {"MKDM":"arts","NR":"文化艺术","XF":"2","YXXF":1.5,
           "BXXF":0,"bxyxxf":0,"XXXF":"2","xxyxxf":9,"xxyxxfR":"1.5"},
          {"MKDM":"optional","NR":"无学分要求","XF":0,"YXXF":0,
           "BXXF":"0.0","bxyxxf":0,"XXXF":0,"xxyxxfR":0},
          {"MKDM":"service","NR":"社会实践","XF":3,"YXXF":"0",
           "BXXF":1,"bxyxxf":"0","XXXF":2,"xxyxxfR":0}
        ]}}
        """#.utf8)
        let grades = try JSONDecoder().decode(SecondClassResponse<SecondClassGrades>.self, from: data).data
        let categories = grades.cj.compactMap(\.category)
        #expect(categories.count == 2)
        let arts = try #require(categories.first)
        #expect(arts.requirements.count == 1)
        #expect(arts.requirements[0].kind == .elective)
        #expect(arts.requirements[0].earnedCredits == Decimal(string: "1.5"))
        #expect(arts.requirements[0].remainingCredits == Decimal(string: "0.5"))
        #expect(!arts.requirements[0].isCompleted)
        #expect(categories[1].requirements.count == 2)
        #expect(categories[1].requirements.allSatisfy { $0.earnedCredits == 0 })
    }

    @Test func businessFailureDoesNotBecomeEmptyTranscript() {
        let data = Data(#"{"code":"403","data":null}"#.utf8)
        #expect(throws: SecondClassError.rejected("403")) {
            try JSONDecoder().decode(SecondClassResponse<SecondClassGrades>.self, from: data)
        }
    }

    @Test(arguments: [#""unknown""#, "-1", "true", "null", #""NaN""#])
    func rejectsInvalidCredits(_ value: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SecondClassNumber.self, from: Data(value.utf8))
        }
    }
}

private final class SecondClassProtocol: URLProtocol, @unchecked Sendable {
    private static let state = ApplicationState()

    static func reset() { state.reset() }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "xg.wust.edu.cn" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let (status, body) = Self.state.response(for: request)
        let headers = ["Content-Type": "application/json"]
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private final class ApplicationState: @unchecked Sendable {
        private let lock = NSLock()
        private var initialized = false

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            initialized = false
        }

        func response(for request: URLRequest) -> (Int, String) {
            lock.lock()
            defer { lock.unlock() }
            guard request.httpMethod == "POST", let url = request.url else { return (400, "{}") }
            switch url.path {
            case "/xsfw/sys/swpubapp/indexmenu/getAppConfig.do":
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                guard items.contains(URLQueryItem(name: "appId", value: "5446046383738452")),
                      items.contains(URLQueryItem(name: "appName", value: "dektapp")) else {
                    return (400, "{}")
                }
                initialized = true
                return (200, #"{"MODULES":[]}"#)
            case "/xsfw/sys/dektapp/modules/cjdcxManage/getCj.do":
                return initialized ? (200, #"{"code":"0","data":{"cj":[]}}"#) : (401, "{}")
            case "/xsfw/sys/dektapp/modules/cjdcxManage/getSzfzpj.do":
                return initialized ? (200, #"{"code":"0","data":{"ZXF":0,"PJ":"测试评价"}}"#) : (401, "{}")
            default:
                return (404, "{}")
            }
        }
    }
}
