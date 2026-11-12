import Foundation
import Testing
@testable import WUSTFoundation

struct LaundryOrderMonitorTests {
    @Test(arguments: [(1200, 120), (450, 60), (240, 30), (120, 0)])
    func respectsRemainingTimeCacheWindows(_ remaining: Int, _ lifetime: Int) async throws {
        let clock = TestClock()
        let source = SnapshotSource(clock: clock, durations: [remaining])
        let monitor = LaundryOrderMonitor(now: { clock.now() }, fetch: { try await source.load() })
        _ = try await monitor.currentSnapshot()
        _ = try await monitor.currentSnapshot()
        #expect(await source.calls == (lifetime == 0 ? 2 : 1))
        if lifetime > 0 {
            clock.advance(lifetime - 1)
            _ = try await monitor.currentSnapshot()
            #expect(await source.calls == 1)
            clock.advance(1)
            _ = try await monitor.currentSnapshot()
            #expect(await source.calls == 2)
        }
    }

    @Test(arguments: [(601, 61), (301, 31), (121, 2)])
    func crossingThresholdUsesShorterCacheWindow(_ remaining: Int, _ elapsed: Int) async throws {
        let clock = TestClock()
        let source = SnapshotSource(clock: clock, durations: [remaining])
        let monitor = LaundryOrderMonitor(now: { clock.now() }, fetch: { try await source.load() })
        _ = try await monitor.currentSnapshot()
        clock.advance(elapsed)
        _ = try await monitor.currentSnapshot()
        #expect(await source.calls == 2)
    }

    @Test func zeroCountdownIsCorrectedWhenServerExtendsOrder() async throws {
        let clock = TestClock()
        let source = SnapshotSource(clock: clock, durations: [1, 180])
        let monitor = LaundryOrderMonitor(now: { clock.now() }, fetch: { try await source.load() })
        let first = try await monitor.currentSnapshot()
        clock.advance(2)
        #expect(first.remainingSeconds(at: clock.now()) == 0)
        let corrected = try await monitor.currentSnapshot()
        #expect(corrected.remainingSeconds == 180)
        #expect(corrected.order.isRunningWasher)
        _ = try await monitor.currentSnapshot()
        #expect(await source.calls == 2)
    }

    @Test func failedCorrectionThrowsAndNextCallRetries() async throws {
        let clock = TestClock()
        let source = SnapshotSource(clock: clock, durations: [240], failsSecondCall: true)
        let monitor = LaundryOrderMonitor(now: { clock.now() }, fetch: { try await source.load() })
        _ = try await monitor.currentSnapshot()
        clock.advance(31)
        await #expect(throws: URLError.self) { try await monitor.currentSnapshot() }
        let retry = try await monitor.currentSnapshot()
        #expect(retry.observedAt == clock.now())
        #expect(await source.calls == 3)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1794229200)

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ seconds: Int) {
        lock.lock()
        defer { lock.unlock() }
        date.addTimeInterval(TimeInterval(seconds))
    }
}

private actor SnapshotSource {
    let clock: TestClock
    let durations: [Int]
    let failsSecondCall: Bool
    private(set) var calls = 0

    init(clock: TestClock, durations: [Int], failsSecondCall: Bool = false) {
        self.clock = clock
        self.durations = durations
        self.failsSecondCall = failsSecondCall
    }

    func load() throws -> LaundryOrderSnapshot {
        calls += 1
        if failsSecondCall, calls == 2 { throw URLError(.notConnectedToInternet) }
        let remaining = durations[min(calls - 1, durations.count - 1)]
        let order = try JSONDecoder().decode(LaundryOrder.self, from: Data(#"{"id":"test","orderType":1,"orderStatus":2,"parentTypeId":"c9892cb4-bd78-40f6-83c2-ba73383b090a"}"#.utf8))
        let observedAt = clock.now()
        return LaundryOrderSnapshot(
            order: order, estimatedCompletionTime: observedAt.addingTimeInterval(TimeInterval(remaining)),
            observedAt: observedAt, remainingSeconds: remaining
        )
    }
}
