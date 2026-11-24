import Foundation
import CoreGraphics
import ImageIO
import CommonCrypto
import Testing
@testable import WUSTFoundation

struct SliderCaptchaTests {
    @Test func translatedDarkenedTargetIsMatchedAndScaled() throws {
        let challenge = try Self.challenge()
        let result = try SliderCaptchaSolver().solve(challenge)
        #expect(result.pixelOffset == 90)
        #expect(result.confidence > 0.99)
        #expect(abs(result.moveLength - 105) < 0.001)
    }

    @Test func invalidBase64IsRejected() {
        let challenge = SliderCaptcha(bigImage: "!", smallImage: "!", tagWidth: 40, yHeight: 0)
        #expect(throws: SliderCaptchaError.invalidImage) { try SliderCaptchaSolver().solve(challenge) }
    }

    @Test func inconsistentGeometryIsRejected() throws {
        let original = try Self.challenge()
        let invalid = SliderCaptcha(bigImage: original.bigImage, smallImage: original.smallImage,
                                    tagWidth: 400, yHeight: 0)
        #expect(throws: SliderCaptchaError.invalidGeometry) { try SliderCaptchaSolver().solve(invalid) }
    }

    @Test func encryptionPreservesPayloadAfterOfficialRandomPrefix() throws {
        let payload = Data(#"{"canvasLength":280,"moveLength":105,"tracks":[]}"#.utf8)
        let key = Data("0123456789abcdef".utf8)
        let encrypted = try #require(Data(base64Encoded: AuthServerEncryption.encrypt(payload, key: String(decoding: key, as: UTF8.self))))
        // The site's random IV is not transmitted. Its receiver discards the random 64-byte prefix.
        let iv = Data(repeating: 0, count: kCCBlockSizeAES128)
        var plaintext = Data(count: encrypted.count)
        let capacity = plaintext.count
        var length = 0
        let status = plaintext.withUnsafeMutableBytes { output in
            encrypted.withUnsafeBytes { input in
                key.withUnsafeBytes { key in
                    iv.withUnsafeBytes { iv in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                key.baseAddress, 16, iv.baseAddress, input.baseAddress, encrypted.count,
                                output.baseAddress, capacity, &length)
                    }
                }
            }
        }
        #expect(status == kCCSuccess)
        plaintext.count = length
        #expect(plaintext.dropFirst(64) == payload)
    }

    @Test func serverRejectionAndBooleanCodeAreNotSuccess() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SliderResponseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let challenge = try Self.challenge()
        let solution = try SliderCaptchaSolver().solve(challenge)
        let service = AuthServerCaptchaService(baseURL: URL(string: "https://slider.test/rejected/")!)
        await #expect(throws: SliderCaptchaError.rejected(0)) {
            try await service.verify(challenge, solution: solution, using: session)
        }
        let invalid = AuthServerCaptchaService(baseURL: URL(string: "https://slider.test/boolean/")!)
        await #expect(throws: SliderCaptchaError.invalidResponse) {
            try await invalid.verify(challenge, solution: solution, using: session)
        }
        let fractional = AuthServerCaptchaService(baseURL: URL(string: "https://slider.test/fractional/")!)
        await #expect(throws: SliderCaptchaError.invalidResponse) {
            try await fractional.verify(challenge, solution: solution, using: session)
        }
        let success = AuthServerCaptchaService(baseURL: URL(string: "https://slider.test/success/")!)
        try await success.verify(challenge, solution: solution, using: session)
    }

    private static func challenge() throws -> SliderCaptcha {
        let width = 240, height = 80, pieceWidth = 40, offset = 90
        var background = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var value = UInt32(truncatingIfNeeded: x * 73856093 ^ y * 19349663)
                value ^= value >> 13
                value &*= 1274126177
                let index = (y * width + x) * 4
                background[index] = UInt8(truncatingIfNeeded: value)
                background[index + 1] = UInt8(truncatingIfNeeded: value >> 8)
                background[index + 2] = UInt8(truncatingIfNeeded: value >> 16)
            }
        }
        var piece = [UInt8](repeating: 0, count: pieceWidth * height * 4)
        for y in 18..<53 {
            for x in 4..<36 {
                let source = (y * width + offset + x) * 4
                let destination = (y * pieceWidth + x) * 4
                for channel in 0..<3 {
                    piece[destination + channel] = background[source + channel]
                    background[source + channel] /= 2
                }
                piece[destination + 3] = 255
            }
        }
        let big = try png(background, width: width, height: height)
        let small = try png(piece, width: pieceWidth, height: height) + Data("0123456789abcdef".utf8)
        return SliderCaptcha(bigImage: big.base64EncodedString(), smallImage: small.base64EncodedString(),
                             tagWidth: pieceWidth, yHeight: 0)
    }

    private static func png(_ pixels: [UInt8], width: Int, height: Int) throws -> Data {
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
                                        bitsPerPixel: 32, bytesPerRow: width * 4,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                                            .union(.byteOrder32Big), provider: provider, decode: nil,
                                        shouldInterpolate: false, intent: .defaultIntent))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private final class SliderResponseProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "slider.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body: String
        if request.url!.path.contains("boolean") { body = #"{"errorCode":true}"# }
        else if request.url!.path.contains("fractional") { body = #"{"errorCode":1.5}"# }
        else if request.url!.path.contains("success") { body = #"{"errorCode":1}"# }
        else { body = #"{"errorCode":0}"# }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
