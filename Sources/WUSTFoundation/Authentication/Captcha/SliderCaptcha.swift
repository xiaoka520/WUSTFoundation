import Foundation

/// A single challenge, bound to the URLSession that fetched it.
public struct SliderCaptcha: Decodable, Sendable {
    public let bigImage: String
    public let smallImage: String
    public let tagWidth: Int
    public let yHeight: Int

    public init(bigImage: String, smallImage: String, tagWidth: Int, yHeight: Int) {
        self.bigImage = bigImage
        self.smallImage = smallImage
        self.tagWidth = tagWidth
        self.yHeight = yHeight
    }

    func imageData() throws -> (background: Data, piece: Data) {
        guard let background = Data(base64Encoded: bigImage),
              let piece = Data(base64Encoded: smallImage),
              !background.isEmpty, piece.count > 16,
              background.count <= 8_000_000, piece.count <= 8_000_000 else {
            throw SliderCaptchaError.invalidImage
        }
        return (background, piece)
    }
}

public enum SliderCaptchaError: Error, Sendable, Equatable {
    case invalidImage
    case invalidGeometry
    case noReliableMatch
    case encryptionFailed
    case invalidResponse
    case unexpectedStatusCode(Int)
    case rejected(Int)
    case invalidAttempts
}

/// Pixel displacement is in original-image coordinates; moveLength is in widget coordinates.
public struct SliderCaptchaSolution: Sendable {
    public let pixelOffset: Int
    public let confidence: Double
    public let canvasLength: Int
    public let moveLength: Double
}
