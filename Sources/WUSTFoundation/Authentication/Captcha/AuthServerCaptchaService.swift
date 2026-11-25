import Foundation
import CommonCrypto

/// New /authserver slider verification. All calls must use the same caller-owned session.
public struct AuthServerCaptchaService: Sendable {
    private let baseURL: URL
    private let referer: URL

    public init(baseURL: URL = URL(string: "https://auth.wust.edu.cn/authserver/")!, referer: URL? = nil) {
        self.baseURL = baseURL
        self.referer = referer ?? baseURL.appendingPathComponent("login")
    }

    /// Establishes an anonymous CAS session. Call before fetching a login form/challenge.
    public func beginSession(using session: URLSession,
                             diagnostics: (@Sendable (SliderCaptchaDiagnostic) -> Void)? = nil) async throws {
        diagnostics?(.phase(.session))
        _ = try await request(path: "login", using: session, diagnostics: diagnostics)
    }

    public func fetchChallenge(using session: URLSession,
                               diagnostics: (@Sendable (SliderCaptchaDiagnostic) -> Void)? = nil) async throws -> SliderCaptcha {
        diagnostics?(.phase(.fetch))
        let data = try await request(path: "common/openSliderCaptcha.htl", using: session, diagnostics: diagnostics)
        diagnostics?(.phase(.decode))
        let challenge = try JSONDecoder().decode(SliderCaptcha.self, from: data)
        let images = try challenge.imageData()
        diagnostics?(.challenge(backgroundBytes: images.background.count, pieceBytes: images.piece.count,
                                tagWidth: challenge.tagWidth, yHeight: challenge.yHeight))
        return challenge
    }

    /// Returns only after the server confirms errorCode == 1; HTTP 200 alone is insufficient.
    public func verify(_ challenge: SliderCaptcha, solution: SliderCaptchaSolution,
                       using session: URLSession) async throws {
        let payload = SliderVerificationPayload(solution: solution)
        try await verify(challenge, payload: payload, using: session)
    }

    func verify(_ challenge: SliderCaptcha, payload: SliderVerificationPayload,
                using session: URLSession,
                diagnostics: (@Sendable (SliderCaptchaDiagnostic) -> Void)? = nil) async throws {
        diagnostics?(.phase(.verification))
        let data = try challenge.imageData()
        // The official component obtains its per-challenge AES key from the PNG trailer.
        let keyBytes = data.piece.suffix(16)
        guard keyBytes.allSatisfy({ $0 >= 33 && $0 <= 126 }) else {
            throw SliderCaptchaError.invalidImage
        }
        let key = String(decoding: keyBytes, as: UTF8.self)
        let sign = try AuthServerEncryption.encrypt(JSONEncoder().encode(payload), key: key)
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "sign", value: sign)]
        guard let encoded = form.percentEncodedQuery else { throw SliderCaptchaError.encryptionFailed }
        let body = Data(encoded.replacingOccurrences(of: "+", with: "%2B").utf8)
        let result = try await request(path: "common/verifySliderCaptcha.htl", body: body, using: session, diagnostics: diagnostics)
        guard let object = try JSONSerialization.jsonObject(with: result) as? [String: Any],
              let value = object["errorCode"] else { throw SliderCaptchaError.invalidResponse }
        let code: Int?
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            code = Int(exactly: number.doubleValue)
        } else if let text = value as? String {
            code = Int(text)
        } else { code = nil }
        guard let code else { throw SliderCaptchaError.invalidResponse }
        diagnostics?(.result(code: code))
        guard code == 1 else { throw SliderCaptchaError.rejected(code) }
    }

    /// Unreliable images refresh independently; maxAttempts bounds verification submissions.
    public func solveAndVerify(using session: URLSession, maxAttempts: Int = 3,
                               diagnostics: (@Sendable (SliderCaptchaDiagnostic) -> Void)? = nil) async throws -> SliderCaptchaSolution {
        guard (1...5).contains(maxAttempts) else { throw SliderCaptchaError.invalidAttempts }
        var lastError: SliderCaptchaError = .noReliableMatch
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            do {
                let (challenge, solution) = try await reliableChallenge(using: session, diagnostics: diagnostics)
                diagnostics?(.match(pixelOffset: solution.pixelOffset, moveLength: solution.moveLength,
                                    confidence: solution.confidence))
                diagnostics?(.phase(.preparing))
                let payload = SliderVerificationPayload(solution: solution)
                let milliseconds = payload.durationMilliseconds
                diagnostics?(.trajectory(points: payload.tracks.count, durationMilliseconds: milliseconds,
                                         verticalMin: payload.tracks.map(\.b).min() ?? 0,
                                         verticalMax: payload.tracks.map(\.b).max() ?? 0))
                diagnostics?(.trajectoryPoints(SliderCaptchaTrace(canvasLength: payload.canvasLength,
                    moveLength: payload.moveLength,
                    tracks: payload.tracks.map { .init(a: $0.a, b: $0.b, c: $0.c) })))
                diagnostics?(.phase(.waiting))
                // Keep elapsed challenge time consistent with the programmatic movement samples.
                try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
                try await verify(challenge, payload: payload, using: session, diagnostics: diagnostics)
                return solution
            } catch {
                let kind: String
                if let slider = error as? SliderCaptchaError { kind = "SliderCaptchaError.\(slider)" }
                else if let network = error as? URLError { kind = "URLError(\(network.code.rawValue))" }
                else { kind = String(reflecting: type(of: error)) }
                diagnostics?(.failure(kind: kind))
                guard let error = error as? SliderCaptchaError else { throw error }
                switch error {
                case .rejected:
                    lastError = error
                    if attempt + 1 == maxAttempts { throw error }
                default: throw error
                }
            }
        }
        throw lastError
    }

    private func reliableChallenge(using session: URLSession,
                                   diagnostics: (@Sendable (SliderCaptchaDiagnostic) -> Void)?) async throws -> (SliderCaptcha, SliderCaptchaSolution) {
        let limit = 10
        for index in 0..<limit {
            try Task.checkCancellation()
            let challenge = try await fetchChallenge(using: session, diagnostics: diagnostics)
            diagnostics?(.phase(.matching))
            do {
                let solution = try SliderCaptchaSolver().solve(challenge, diagnostics: diagnostics)
                return (challenge, solution)
            } catch SliderCaptchaError.noReliableMatch {
                diagnostics?(.challengeDiscarded(count: index + 1, limit: limit))
                // No movement wait or verification POST for an unreliable image.
            }
        }
        throw SliderCaptchaError.challengeRefreshLimitExceeded(limit)
    }

    private func request(path: String, body: Data? = nil, using session: URLSession,
                         diagnostics: (@Sendable (SliderCaptchaDiagnostic) -> Void)? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = 20
        AuthServerRequestHeaders.apply(to: &request, ajax: path != "login", referer: path == "login" ? nil : referer)
        if body != nil { request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type") }
        diagnostics?(.requestProfile(name: "Safari-compatible/18.0"))
        diagnostics?(.request(endpoint: path, cookieCount: session.configuration.httpCookieStorage?.cookies?.count ?? 0))
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            diagnostics?(.httpResponse(endpoint: path, status: http.statusCode,
                                       expectedHost: http.url?.host == request.url?.host,
                                       cookieCount: session.configuration.httpCookieStorage?.cookies?.count ?? 0))
        }
        guard let response = response as? HTTPURLResponse,
              response.url?.host == request.url?.host else { throw SliderCaptchaError.invalidResponse }
        guard response.statusCode == 200 else { throw SliderCaptchaError.unexpectedStatusCode(response.statusCode) }
        return data
    }
}

struct SliderVerificationPayload: Encodable {
    struct Point: Encodable { let a: Double; let b: Double; let c: Int }
    let canvasLength: Int
    let moveLength: Double
    let tracks: [Point]

    init(solution: SliderCaptchaSolution) {
        var random = SystemRandomNumberGenerator()
        self.init(solution: solution, using: &random)
    }

    init<R: RandomNumberGenerator>(solution: SliderCaptchaSolution, using random: inout R) {
        canvasLength = solution.canvasLength
        moveLength = solution.moveLength
        let duration = 1_400
        // Sixty movement intervals plus the starting point, totaling 1.4 seconds.
        let steps = 60
        let originalDuration = (1...steps).reduce(0) { $0 + 24 + $1 % 5 }
        var points = [Point(a: 0, b: 0, c: 0)]
        var originalElapsed = 0
        var scaledElapsed = 0
        let direction = Bool.random(using: &random) ? 1.0 : -1.0
        let drift = Double.random(in: 6...12, using: &random)
        var noise = 0.0
        for step in 1...steps {
            originalElapsed += 24 + step % 5
            // Scale cumulative timestamps to preserve the exact total after rounding.
            let timestamp = originalElapsed * duration / originalDuration
            let progress = Double(step) / Double(steps)
            // One-sided drift with small correlated noise, rather than large up/down jumps.
            noise = max(-0.8, min(0.8, noise * 0.6 + Double.random(in: -0.45...0.45, using: &random)))
            let vertical = direction * max(0, min(drift + 1, drift * progress + noise)).rounded()
            let verticalOffset: Double
            if step < steps {
                let magnitude = Double(Int.random(in: 1...99, using: &random)) / 1_000
                let sign = Bool.random(using: &random) ? 1.0 : -1.0
                // Keep samples at the baseline on the chosen side of the trajectory.
                verticalOffset = magnitude * (vertical == 0 ? direction : sign)
            } else {
                verticalOffset = 0
            }
            points.append(Point(a: solution.moveLength * progress,
                                b: vertical + verticalOffset,
                                c: timestamp - scaledElapsed))
            scaledElapsed = timestamp
        }
        tracks = points
    }

    var durationMilliseconds: Int { tracks.reduce(0) { $0 + $1.c } }
}

enum AuthServerEncryption {
    static func encrypt(_ payload: Data, key: String) throws -> String {
        let keyData = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard [16, 24, 32].contains(keyData.count) else { throw SliderCaptchaError.encryptionFailed }
        let alphabet = Array("ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678".utf8)
        let prefix = Data((0..<64).map { _ in alphabet.randomElement()! })
        let iv = Data((0..<16).map { _ in alphabet.randomElement()! })
        let plaintext = prefix + payload
        var output = Data(count: plaintext.count + kCCBlockSizeAES128)
        let capacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { destination in
            plaintext.withUnsafeBytes { source in
                keyData.withUnsafeBytes { key in
                    iv.withUnsafeBytes { iv in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding), key.baseAddress, keyData.count,
                                iv.baseAddress, source.baseAddress, plaintext.count,
                                destination.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw SliderCaptchaError.encryptionFailed }
        output.count = written
        return output.base64EncodedString()
    }
}
