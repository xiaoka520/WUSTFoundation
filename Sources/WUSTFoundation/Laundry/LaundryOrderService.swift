import Foundation

public struct LaundryOrderService: Sendable {
    private let api: LaundryAPI

    public init() { api = LaundryAPI(profile: .safari) }
    public init(session: URLSession) { api = LaundryAPI(profile: .safari, session: session) }

    public func fetchOrders(credential: LaundryCredential, page: Int = 1) async throws -> LaundryOrderPage {
        guard page > 0, page <= Int.max / 10 else { throw LaundryQueryError.invalidQuery }
        let response: LaundryAPI.Response<OrderPagePayload> = try await authenticatedRequest(
            "order/list", method: "GET",
            fields: ["page": String(page), "pageSize": "10"], credential: credential
        )
        guard let payload = response.data, payload.total >= 0 else { throw LaundryQueryError.invalidResponse }
        let nextPage = !payload.items.isEmpty && page * 10 < payload.total ? page + 1 : nil
        return LaundryOrderPage(total: payload.total, items: payload.items, nextPage: nextPage)
    }

    public func fetchOrderDetail(
        orderID: String, credential: LaundryCredential
    ) async throws -> LaundryOrderSnapshot {
        guard !orderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LaundryQueryError.invalidQuery
        }
        let response: LaundryAPI.Response<OrderDetailPayload> = try await authenticatedRequest(
            "order/detail", method: "POST", fields: ["orderId": orderID], credential: credential
        )
        guard let payload = response.data, payload.order.id == orderID else {
            throw LaundryQueryError.invalidResponse
        }
        let completionTime = try Self.completionDate(payload.completeTime)
        let seconds: Int?
        if payload.order.isRunningWasher, let completionTime {
            let duration = max(0, completionTime.timeIntervalSince(response.serverDate).rounded(.up))
            guard duration < Double(Int.max) else { throw LaundryQueryError.invalidResponse }
            seconds = Int(duration)
        } else {
            seconds = nil
        }
        return LaundryOrderSnapshot(
            order: payload.order, estimatedCompletionTime: completionTime,
            observedAt: response.observedAt, remainingSeconds: seconds
        )
    }

    public func fetchRunningWashers(credential: LaundryCredential) async throws -> [LaundryOrderSnapshot] {
        var page: Int? = 1
        var seenIDs = Set<String>()
        var orders: [LaundryOrder] = []
        while let current = page {
            let result = try await fetchOrders(credential: credential, page: current)
            let newOrders = result.items.filter { seenIDs.insert($0.id).inserted }
            orders += newOrders.filter(\.isRunningWasher)
            page = newOrders.isEmpty ? nil : result.nextPage
        }
        var snapshots: [LaundryOrderSnapshot] = []
        for order in orders {
            let snapshot = try await fetchOrderDetail(orderID: order.id, credential: credential)
            if snapshot.order.isRunningWasher { snapshots.append(snapshot) }
        }
        return snapshots
    }

    private func authenticatedRequest<Payload: Decodable>(
        _ path: String, method: String, fields: [String: String], credential: LaundryCredential
    ) async throws -> LaundryAPI.Response<Payload> {
        guard !credential.token.isEmpty else { throw LaundryAuthError.loginRequired }
        var fields = fields
        fields["token"] = credential.token
        do {
            return try await api.request(path, method: method, fields: fields)
        } catch LaundryQueryError.rejected(2) {
            throw LaundryAuthError.loginRequired
        }
    }

    private static func completionDate(_ value: String?) throws -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            throw LaundryQueryError.invalidResponse
        }
        return date
    }

    private struct OrderPagePayload: Decodable {
        let total: Int
        let items: [LaundryOrder]
    }

    private struct OrderDetailPayload: Decodable {
        let order: LaundryOrder
        let completeTime: String?

        private enum CodingKeys: String, CodingKey { case completeTime }

        init(from decoder: Decoder) throws {
            order = try LaundryOrder(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            completeTime = try container.decodeIfPresent(String.self, forKey: .completeTime)
        }
    }
}
