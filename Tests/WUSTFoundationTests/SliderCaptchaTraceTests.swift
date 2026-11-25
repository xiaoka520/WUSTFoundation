import Foundation
import Testing
@testable import WUSTFoundation

struct SliderCaptchaTraceTests {
    @Test func diagnosticJSONPreservesEveryPayloadPoint() throws {
        let trace = SliderCaptchaTrace(canvasLength: 280, moveLength: 99, tracks: [
            .init(a: 0, b: 0, c: 0), .init(a: 101.25, b: -2.5, c: 31), .init(a: 99, b: -2, c: 47)
        ])
        let data = try JSONEncoder().encode(trace)
        let decoded = try JSONDecoder().decode(SliderCaptchaTrace.self, from: data)
        #expect(decoded.canvasLength == 280)
        #expect(decoded.moveLength == 99)
        #expect(decoded.tracks.map(\.a) == [0, 101.25, 99])
        #expect(decoded.tracks.map(\.b) == [0, -2.5, -2])
        #expect(decoded.tracks.map(\.c) == [0, 31, 47])
    }
}
