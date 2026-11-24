import Foundation
import CoreGraphics
import ImageIO
import Accelerate

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
        let piece = fullHeight && originalPiece.height != background.height
            ? try Raster(data: data.piece, height: background.height)
            : originalPiece
        let originY = fullHeight ? 0 : challenge.yHeight
        guard originY + piece.height <= background.height else { throw SliderCaptchaError.invalidGeometry }

        var samples: [(x: Int, y: Int, value: Double)] = []
        for y in stride(from: 2, to: piece.height - 2, by: 2) {
            for x in stride(from: 2, to: piece.width - 2, by: 2) {
                // Erode the alpha mask to exclude the white outline and interpolated edge.
                guard piece.alpha(x: x, y: y) >= 250,
                      piece.alpha(x: x - 2, y: y) >= 250,
                      piece.alpha(x: x + 2, y: y) >= 250,
                      piece.alpha(x: x, y: y - 2) >= 250,
                      piece.alpha(x: x, y: y + 2) >= 250 else { continue }
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
        let sampleIndices = samples.map { $0.y * background.width + $0.x }
        var target = [Double](repeating: 0, count: samples.count)
        let sampleCount = samples.count, maximumOffset = background.width - piece.width
        scores.reserveCapacity(maximumOffset + 1)
        // Geometry above guarantees each gathered index stays within the background raster.
        background.grayValues.withUnsafeBufferPointer { backgroundBuffer in
            sampleIndices.withUnsafeBufferPointer { indexBuffer in
                values.withUnsafeBufferPointer { valueBuffer in
                    target.withUnsafeMutableBufferPointer { targetBuffer in
                        let pixels = backgroundBuffer.baseAddress!, indices = indexBuffer.baseAddress!
                        let template = valueBuffer.baseAddress!, gathered = targetBuffer.baseAddress!
                        var offset = 0
                        while offset <= maximumOffset {
                            var index = 0
                            while index < sampleCount {
                                gathered[index] = pixels[indices[index] + offset]
                                index += 1
                            }
                            var sum = 0.0, squares = 0.0, covariance = 0.0
                            vDSP_sveD(gathered, 1, &sum, vDSP_Length(sampleCount))
                            vDSP_svesqD(gathered, 1, &squares, vDSP_Length(sampleCount))
                            vDSP_dotprD(template, 1, gathered, 1, &covariance, vDSP_Length(sampleCount))
                            let targetVariance = squares - sum * sum / count
                            let score = targetVariance > count ? covariance / sqrt(variance * targetVariance) : -1
                            scores.append((offset, score))
                            offset += 1
                        }
                    }
                }
            }
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
    let grayValues: [Double]

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
        let count = width * height
        var gray = [Double](repeating: 0, count: count)
        var channel = [Double](repeating: 0, count: count)
        pixels.withUnsafeBufferPointer { input in
            gray.withUnsafeMutableBufferPointer { output in
                channel.withUnsafeMutableBufferPointer { scratch in
                    let source = input.baseAddress!, destination = output.baseAddress!, temporary = scratch.baseAddress!
                    vDSP_vfltu8D(source, 4, destination, 1, vDSP_Length(count))
                    var weight = 0.299
                    vDSP_vsmulD(destination, 1, &weight, destination, 1, vDSP_Length(count))
                    vDSP_vfltu8D(source + 1, 4, temporary, 1, vDSP_Length(count))
                    weight = 0.587
                    vDSP_vsmaD(temporary, 1, &weight, destination, 1, destination, 1, vDSP_Length(count))
                    vDSP_vfltu8D(source + 2, 4, temporary, 1, vDSP_Length(count))
                    weight = 0.114
                    vDSP_vsmaD(temporary, 1, &weight, destination, 1, destination, 1, vDSP_Length(count))
                }
            }
        }
        self.width = width
        self.height = height
        self.pixels = pixels
        self.grayValues = gray
    }

    func alpha(x: Int, y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
    func gray(x: Int, y: Int) -> Double {
        grayValues[y * width + x]
    }
}
