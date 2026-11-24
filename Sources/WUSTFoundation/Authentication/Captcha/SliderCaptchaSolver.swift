import Foundation
import CoreGraphics
import ImageIO

/// Matches the opaque interior of the piece against the background using normalized correlation.
/// Unlike text recognition, this is invariant to the challenge's darkened target region.
public struct SliderCaptchaSolver: Sendable {
    public init() {}

    public func solve(_ challenge: SliderCaptcha, canvasLength: Int = 280) throws -> SliderCaptchaSolution {
        guard (100...2048).contains(canvasLength) else { throw SliderCaptchaError.invalidGeometry }
        let data = try challenge.imageData()
        let background = try Raster(data: data.background)
        let originalPiece = try Raster(data: data.piece)
        guard challenge.tagWidth > 0, challenge.tagWidth == originalPiece.width,
              originalPiece.width < background.width, challenge.yHeight >= 0 else {
            throw SliderCaptchaError.invalidGeometry
        }
        // The website draws both full-height strips to the same canvas height.
        let fullHeight = abs(originalPiece.height - background.height) <= 2
        let piece = fullHeight
            ? try Raster(data: data.piece, height: background.height)
            : originalPiece
        let originY = fullHeight ? 0 : challenge.yHeight
        guard originY + piece.height <= background.height else { throw SliderCaptchaError.invalidGeometry }

        var samples: [(x: Int, y: Int, value: Double)] = []
        for y in stride(from: 2, to: piece.height - 2, by: 2) {
            for x in stride(from: 2, to: piece.width - 2, by: 2) {
                // Erode the alpha mask to exclude the white outline and interpolated edge.
                guard [(x,y), (x-2,y), (x+2,y), (x,y-2), (x,y+2)].allSatisfy({
                    piece.alpha(x: $0.0, y: $0.1) >= 250
                }) else { continue }
                samples.append((x, y + originY, piece.gray(x: x, y: y)))
            }
        }
        guard samples.count >= 32 else { throw SliderCaptchaError.invalidImage }
        let count = Double(samples.count)
        let mean = samples.reduce(0) { $0 + $1.value } / count
        let values = samples.map { $0.value - mean }
        let variance = values.reduce(0) { $0 + $1 * $1 }
        guard variance > count else { throw SliderCaptchaError.noReliableMatch }
        var scores: [(x: Int, score: Double)] = []
        for offset in 0...(background.width - piece.width) {
            var sum = 0.0, squares = 0.0, covariance = 0.0
            for index in samples.indices {
                let sample = samples[index]
                let value = background.gray(x: offset + sample.x, y: sample.y)
                sum += value
                squares += value * value
                covariance += values[index] * value
            }
            let targetVariance = squares - sum * sum / count
            let score = targetVariance > count ? covariance / sqrt(variance * targetVariance) : -1
            scores.append((offset, score))
        }
        guard let best = scores.max(by: { $0.score < $1.score }), best.score.isFinite,
              best.score >= 0.65 else { throw SliderCaptchaError.noReliableMatch }
        let alternative = scores.filter { abs($0.x - best.x) > max(8, piece.width / 4) }
            .map(\.score).max() ?? -1
        guard best.score - alternative >= 0.03 else { throw SliderCaptchaError.noReliableMatch }
        let moveLength = Double(best.x) * Double(canvasLength) / Double(background.width)
        guard moveLength > 0, moveLength + 40 <= Double(canvasLength) else {
            throw SliderCaptchaError.invalidGeometry
        }
        return SliderCaptchaSolution(pixelOffset: best.x, confidence: best.score,
                                     canvasLength: canvasLength, moveLength: moveLength)
    }
}

private struct Raster {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(data: Data, height requestedHeight: Int? = nil) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let sourceHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              (8...2048).contains(width), (8...2048).contains(sourceHeight),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SliderCaptchaError.invalidImage
        }
        let height = requestedHeight ?? sourceHeight
        guard (8...2048).contains(height) else { throw SliderCaptchaError.invalidGeometry }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                              | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw SliderCaptchaError.invalidImage }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func alpha(x: Int, y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
    func gray(x: Int, y: Int) -> Double {
        let index = (y * width + x) * 4
        return 0.299 * Double(pixels[index]) + 0.587 * Double(pixels[index + 1])
            + 0.114 * Double(pixels[index + 2])
    }
}
