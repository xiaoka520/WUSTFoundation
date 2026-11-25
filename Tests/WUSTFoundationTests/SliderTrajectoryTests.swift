import Testing
@testable import WUSTFoundation

struct SliderTrajectoryTests {
    @Test(arguments: [0.5, 46.0, 56.0, 94.0, 98.0])
    func shortMovementsTakeOnePointFourSeconds(distance: Double) throws {
        let solution = SliderCaptchaSolution(pixelOffset: 90, confidence: 0.9,
                                             canvasLength: 280, moveLength: distance)
        let payload = SliderVerificationPayload(solution: solution)
        #expect(payload.tracks.count == 61)
        #expect(payload.durationMilliseconds == 1_400)
        let first = try #require(payload.tracks.first)
        let last = try #require(payload.tracks.last)
        #expect(first.a == 0 && first.b == 0 && first.c == 0)
        #expect(last.a == distance)
        #expect(payload.tracks.dropFirst().allSatisfy { $0.c > 0 })
        #expect(zip(payload.tracks, payload.tracks.dropFirst()).allSatisfy { $0.a <= $1.a })
        #expect(payload.tracks.allSatisfy { (0...distance).contains($0.a) && abs($0.b) <= 13.099 })
    }

    @Test func longMovementAlsoTakesOnePointFourSecondsWithDenserPoints() {
        let solution = SliderCaptchaSolution(pixelOffset: 380, confidence: 0.9,
                                             canvasLength: 280, moveLength: 183)
        let payload = SliderVerificationPayload(solution: solution)
        #expect(payload.tracks.count == 61)
        #expect(payload.durationMilliseconds == 1_400)
        #expect(payload.tracks.dropFirst().allSatisfy { $0.c > 0 })
        #expect(payload.tracks.last?.a == 183)
    }

    @Test func smallJitterStaysOnOneSideWithoutLargeReversals() throws {
        for seed in 1...64 {
            for distance in [12.0, 167.0, 239.0] {
                var random = SeededRandom(state: UInt64(seed))
                let solution = SliderCaptchaSolution(pixelOffset: 380, confidence: 0.9,
                                                     canvasLength: 280, moveLength: distance)
                let payload = SliderVerificationPayload(solution: solution, using: &random)
                #expect(payload.tracks.count == 61)
                let end = try #require(payload.tracks.last)
                let direction = end.b > 0 ? 1.0 : -1.0
                let deltas = zip(payload.tracks, payload.tracks.dropFirst()).map { $1.b - $0.b }
                #expect(deltas.allSatisfy { abs($0) <= 2.198 + 1e-10 })
                #expect(payload.tracks.allSatisfy { $0.b * direction >= 0 && abs($0.b) <= 13.099 })
                #expect((5...13).contains(abs(end.b)))
                #expect(end.a == distance)
                #expect(payload.durationMilliseconds == 1_400)
            }
        }
    }

    @Test func verticalOffsetsAreSmallAndLeaveHorizontalPositionsAndTimingIntact() throws {
        for distance in [0.5, 47.933, 167.0, 239.0] {
            var random = SeededRandom(state: 42)
            let solution = SliderCaptchaSolution(pixelOffset: 0, confidence: 0.9,
                                                 canvasLength: 280, moveLength: distance)
            let payload = SliderVerificationPayload(solution: solution, using: &random)
            #expect(payload.tracks.count == 61)
            #expect(payload.tracks.first?.a == 0)
            #expect(payload.tracks.last?.a == distance)
            #expect(payload.tracks.first?.b == 0)
            let end = try #require(payload.tracks.last)
            #expect(end.b == end.b.rounded())
            #expect((0...60).allSatisfy { index in
                payload.tracks[index].a == distance * (Double(index) / 60)
            })
            let offsets = payload.tracks.dropFirst().dropLast().map { $0.b - $0.b.rounded() }
            #expect(offsets.allSatisfy { abs($0) > 0 && abs($0) <= 0.099 + 1e-10 })
            #expect(offsets.allSatisfy { abs($0 * 1_000 - ($0 * 1_000).rounded()) < 1e-8 })
            #expect(offsets.contains { $0 > 0 })
            #expect(offsets.contains { $0 < 0 })
            #expect(zip(payload.tracks, payload.tracks.dropFirst()).allSatisfy { $0.a < $1.a })
            #expect(payload.tracks.allSatisfy { (0...distance).contains($0.a) })
            #expect(payload.durationMilliseconds == 1_400)
        }
    }
}

private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
