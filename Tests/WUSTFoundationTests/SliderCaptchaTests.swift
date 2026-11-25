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

    @Test func rejectionDiagnosticsKeepHTTPAndBusinessCodeSeparate() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SliderResponseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let challenge = try Self.challenge()
        let solution = try SliderCaptchaSolver().solve(challenge)
        let recorder = SliderDiagnosticRecorder()
        let service = AuthServerCaptchaService(baseURL: URL(string: "https://slider.test/rejected/")!)
        await #expect(throws: SliderCaptchaError.rejected(0)) {
            try await service.verify(challenge, payload: SliderVerificationPayload(solution: solution),
                                     using: session, diagnostics: { recorder.record($0) })
        }
        let events = recorder.snapshot()
        #expect(events.contains { if case .httpResponse(_, 200, true, _) = $0 { true } else { false } })
        #expect(events.contains { if case .result(0) = $0 { true } else { false } })
        #expect(events.contains { if case .request("common/verifySliderCaptcha.htl", _) = $0 { true } else { false } })
    }

    @Test func ambiguousMatchReportsTheFailedReliabilityRule() throws {
        let challenge = try Self.challenge(duplicateTarget: true)
        let recorder = SliderDiagnosticRecorder()
        #expect(throws: SliderCaptchaError.noReliableMatch) {
            try SliderCaptchaSolver().solve(challenge, diagnostics: { recorder.record($0) })
        }
        let events = recorder.snapshot()
        #expect(events.contains {
            if case .candidates(_, let best, let alternative) = $0 {
                return best > 0.99 && alternative > 0.99 && abs(best - alternative) < 0.03
            }
            return false
        })
        #expect(events.contains {
            if case .matchingRejected("最高分与竞争位置分差不足0.03") = $0 { true } else { false }
        })
    }

    @Test func unreliableImagesDoNotConsumeTheVerificationBudget() async throws {
        let fixture = try Self.retryFixture(rejected: false)
        defer { fixture.session.invalidateAndCancel(); SliderRefreshProtocol.remove(fixture.host) }
        let result = try await AuthServerCaptchaService(baseURL: fixture.url)
            .solveAndVerify(using: fixture.session, maxAttempts: 1)
        #expect(result.pixelOffset == 90)
        #expect(SliderRefreshProtocol.counts(fixture.host) == [3, 1])
    }

    @Test func unreliableImageRefreshesHaveAnIndependentStopLimit() async throws {
        let fixture = try Self.retryFixture(rejected: false, alwaysAmbiguous: true)
        defer { fixture.session.invalidateAndCancel(); SliderRefreshProtocol.remove(fixture.host) }
        await #expect(throws: SliderCaptchaError.challengeRefreshLimitExceeded(10)) {
            try await AuthServerCaptchaService(baseURL: fixture.url)
                .solveAndVerify(using: fixture.session, maxAttempts: 3)
        }
        #expect(SliderRefreshProtocol.counts(fixture.host) == [10, 0])
    }

    @Test func serverRejectionStillConsumesOneVerification() async throws {
        let fixture = try Self.retryFixture(rejected: true)
        defer { fixture.session.invalidateAndCancel(); SliderRefreshProtocol.remove(fixture.host) }
        await #expect(throws: SliderCaptchaError.rejected(0)) {
            try await AuthServerCaptchaService(baseURL: fixture.url)
                .solveAndVerify(using: fixture.session, maxAttempts: 1)
        }
        #expect(SliderRefreshProtocol.counts(fixture.host) == [3, 1])
    }

    private static func retryFixture(rejected: Bool, alwaysAmbiguous: Bool = false) throws
        -> (session: URLSession, url: URL, host: String) {
        func encoded(_ challenge: SliderCaptcha) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["bigImage": challenge.bigImage,
                "smallImage": challenge.smallImage, "tagWidth": challenge.tagWidth, "yHeight": challenge.yHeight])
        }
        let ambiguous = try encoded(challenge(duplicateTarget: true))
        let valid = try encoded(challenge())
        let host = UUID().uuidString.lowercased() + ".slider-refresh.test"
        SliderRefreshProtocol.register(host, images: alwaysAmbiguous ? [ambiguous] : [ambiguous, ambiguous, valid],
                                       code: rejected ? 0 : 1)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SliderRefreshProtocol.self]
        return (URLSession(configuration: configuration), URL(string: "https://\(host)/")!, host)
    }

    static func challenge(duplicateTarget: Bool = false) throws -> SliderCaptcha {
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
        if duplicateTarget {
            for y in 0..<height {
                for x in 0..<pieceWidth {
                    for channel in 0..<4 {
                        background[(y * width + 160 + x) * 4 + channel] = background[(y * width + offset + x) * 4 + channel]
                    }
                }
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

private final class SliderDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SliderCaptchaDiagnostic] = []
    func record(_ event: SliderCaptchaDiagnostic) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }
    func snapshot() -> [SliderCaptchaDiagnostic] {
        lock.lock()
        defer { lock.unlock() }
        return events
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

private final class SliderRefreshProtocol: URLProtocol, @unchecked Sendable {
    private struct Scenario { let images: [Data]; let code: Int; var fetches = 0; var posts = 0 }
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var values: [String: Scenario] = [:]
    }
    private static let registry = Registry()
    static func register(_ host: String, images: [Data], code: Int) {
        registry.lock.lock(); defer { registry.lock.unlock() }
        registry.values[host] = Scenario(images: images, code: code)
    }
    static func remove(_ host: String) {
        registry.lock.lock(); defer { registry.lock.unlock() }
        registry.values.removeValue(forKey: host)
    }
    static func counts(_ host: String) -> [Int] {
        registry.lock.lock(); defer { registry.lock.unlock() }
        guard let value = registry.values[host] else { return [] }
        return [value.fetches, value.posts]
    }
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".slider-refresh.test") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.registry.lock.lock()
        guard var scenario = Self.registry.values[url.host ?? ""] else {
            Self.registry.lock.unlock()
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let data: Data
        if url.path.hasSuffix("openSliderCaptcha.htl") {
            data = scenario.images[min(scenario.fetches, scenario.images.count - 1)]
            scenario.fetches += 1
        } else {
            scenario.posts += 1
            data = Data("{\"errorCode\":\(scenario.code)}".utf8)
        }
        Self.registry.values[url.host ?? ""] = scenario
        Self.registry.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
