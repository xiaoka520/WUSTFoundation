import Foundation
import Testing
@testable import WUSTFoundation

struct LaundryOrderTests {
    private func service() -> LaundryOrderService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LaundryOrderProtocol.self]
        return LaundryOrderService(session: URLSession(configuration: configuration))
    }

    private var credential: LaundryCredential {
        LaundryCredential(userID: "fixture", firstVerifiedAt: .now, lastVerifiedAt: .now, token: "fixture+token")
    }

    @Test func findsRunningWasherOnLaterPageAndUsesServerClock() async throws {
        let snapshots = try await service().fetchRunningWashers(credential: credential)
        #expect(snapshots.count == 1)
        let snapshot = try #require(snapshots.first)
        #expect(snapshot.order.id == "running-washer")
        #expect(snapshot.remainingSeconds == 142)
        #expect(snapshot.remainingSeconds(at: snapshot.observedAt.addingTimeInterval(10)) == 132)
        #expect(snapshot.remainingSeconds(at: snapshot.observedAt.addingTimeInterval(200)) == 0)
        #expect(snapshot.order.isRunningWasher)
        #expect(snapshot.estimatedCompletionTime == Date(timeIntervalSince1970: 1794229342))
    }

    @Test func completedOrderAndMissingEndTimeHaveNoCountdown() async throws {
        let completed = try await service().fetchOrderDetail(orderID: "completed", credential: credential)
        #expect(completed.remainingSeconds == nil)
        #expect(!completed.order.isRunningWasher)
        let unknown = try await service().fetchOrderDetail(orderID: "unknown-time", credential: credential)
        #expect(unknown.order.isRunningWasher)
        #expect(unknown.estimatedCompletionTime == nil)
        #expect(unknown.remainingSeconds == nil)
    }

    @Test func expiredCredentialRequiresLogin() async throws {
        let expired = LaundryCredential(
            userID: "fixture", firstVerifiedAt: .now, lastVerifiedAt: .now, token: "expired"
        )
        await #expect(throws: LaundryAuthError.loginRequired) {
            try await service().fetchOrders(credential: expired)
        }
    }
}

private final class LaundryOrderProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "userapi.qiekj.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let url = try #require(request.url)
            let fields: [URLQueryItem]
            if request.httpMethod == "GET" {
                fields = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            } else {
                var form = URLComponents()
                form.percentEncodedQuery = String(decoding: try bodyData(), as: UTF8.self)
                fields = form.queryItems ?? []
            }
            let token = fields.first { $0.name == "token" }?.value
            let data: [String: Any]
            if token == "expired" {
                data = ["code": 2, "data": NSNull()]
            } else {
                guard token == "fixture+token" else { throw URLError(.userAuthenticationRequired) }
                switch (request.httpMethod, url.path) {
                case ("GET", "/order/list"):
                    let page = fields.first { $0.name == "page" }?.value
                    let items = page == "1" ? (0..<9).map { order(id: "done-\($0)", status: 3) } +
                        [order(id: "running-water", washer: false)] :
                        [order(id: "running-washer"), order(id: "completed", status: 3)]
                    data = ["code": 0, "data": ["total": 12, "items": items]]
                case ("POST", "/order/detail"):
                    let id = fields.first { $0.name == "orderId" }?.value ?? ""
                    var detail = order(id: id, status: id == "completed" ? 3 : 2)
                    if id != "unknown-time" { detail["completeTime"] = "2026-11-09 21:02:22" }
                    data = ["code": 0, "data": detail]
                default:
                    throw URLError(.unsupportedURL)
                }
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
                "Content-Type": "application/json", "Date": "Mon, 09 Nov 2026 13:00:00 GMT"
            ])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: data))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func bodyData() throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }

    private func order(id: String, status: Int = 2, washer: Bool = true) -> [String: Any] {
        [
            "id": id, "orderType": 1, "orderStatus": status, "machineName": "测试设备",
            "parentTypeId": washer ? "c9892cb4-bd78-40f6-83c2-ba73383b090a" : "other"
        ]
    }
}
