import Foundation

/// The exact numeric payload before encryption, without challenge images or session secrets.
public struct SliderCaptchaTrace: Codable, Sendable {
    public struct Point: Codable, Sendable {
        public let a: Double
        public let b: Double
        public let c: Int
    }
    public let canvasLength: Int
    public let moveLength: Double
    public let tracks: [Point]
}
