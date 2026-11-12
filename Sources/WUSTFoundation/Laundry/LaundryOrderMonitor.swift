import Foundation

public actor LaundryOrderMonitor {
    private let fetch: @Sendable () async throws -> LaundryOrderSnapshot
    private let now: @Sendable () -> Date
    private var cached: LaundryOrderSnapshot?
    private var pending: (id: UUID, task: Task<LaundryOrderSnapshot, Error>)?

    public init(
        orderID: String, credential: LaundryCredential,
        service: LaundryOrderService = LaundryOrderService(),
        initialSnapshot: LaundryOrderSnapshot? = nil
    ) {
        fetch = { try await service.fetchOrderDetail(orderID: orderID, credential: credential) }
        now = { Date() }
        cached = initialSnapshot?.order.id == orderID ? initialSnapshot : nil
    }

    init(
        now: @escaping @Sendable () -> Date,
        fetch: @escaping @Sendable () async throws -> LaundryOrderSnapshot
    ) {
        self.now = now
        self.fetch = fetch
    }

    public func currentSnapshot() async throws -> LaundryOrderSnapshot {
        try Task.checkCancellation()
        let date = now()
        if let cached, let remaining = cached.remainingSeconds(at: date) {
            let age = date.timeIntervalSince(cached.observedAt)
            if age >= 0, age < Self.cacheLifetime(remainingSeconds: remaining) { return cached }
        }

        let operation: (id: UUID, task: Task<LaundryOrderSnapshot, Error>)
        if let pending {
            operation = pending
        } else {
            let fetch = self.fetch
            operation = (UUID(), Task { try await fetch() })
            pending = operation
        }
        do {
            let snapshot = try await operation.task.value
            if pending?.id == operation.id {
                cached = snapshot
                pending = nil
            }
            try Task.checkCancellation()
            return snapshot
        } catch {
            if pending?.id == operation.id { pending = nil }
            throw error
        }
    }

    private static func cacheLifetime(remainingSeconds: Int) -> TimeInterval {
        if remainingSeconds > 600 { return 120 }
        if remainingSeconds > 300 { return 60 }
        if remainingSeconds > 120 { return 30 }
        return 0
    }
}
