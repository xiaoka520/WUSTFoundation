import Foundation
import CommonCrypto

/// New /authserver slider verification. All calls must use the same caller-owned session.
public struct AuthServerCaptchaService: Sendable {
    private let baseURL: URL

    public init(baseURL: URL = URL(string: "https://auth.wust.edu.cn/authserver/")!) {
        self.baseURL = baseURL
    }

    /// Establishes an anonymous CAS session. Call before fetching a login form/challenge.
    public func beginSession(using session: URLSession) async throws {
        _ = try await request(path: "login", using: session)
    }

    public func fetchChallenge(using session: URLSession) async throws -> SliderCaptcha {
        let data = try await request(path: "common/openSliderCaptcha.htl", using: session)
        let challenge = try JSONDecoder().decode(SliderCaptcha.self, from: data)
        _ = try challenge.imageData()
        return challenge
    }

    /// Returns only after the server confirms errorCode == 1; HTTP 200 alone is insufficient.
    public func verify(_ challenge: SliderCaptcha, solution: SliderCaptchaSolution,
                       using session: URLSession) async throws {
        let payload = SliderVerificationPayload(solution: solution)
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
        let result = try await request(path: "common/verifySliderCaptcha.htl", body: body, using: session)
        guard let object = try JSONSerialization.jsonObject(with: result) as? [String: Any],
              let value = object["errorCode"] else { throw SliderCaptchaError.invalidResponse }
        let code: Int?
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            code = Int(exactly: number.doubleValue)
        } else if let text = value as? String {
            code = Int(text)
        } else { code = nil }
        guard let code else { throw SliderCaptchaError.invalidResponse }
        guard code == 1 else { throw SliderCaptchaError.rejected(code) }
    }

    /// Fetches a fresh challenge on each bounded retry. Does not submit account credentials.
    public func solveAndVerify(using session: URLSession, maxAttempts: Int = 3) async throws -> SliderCaptchaSolution {
        guard (1...5).contains(maxAttempts) else { throw SliderCaptchaError.invalidAttempts }
        var lastError: SliderCaptchaError = .noReliableMatch
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            let challenge = try await fetchChallenge(using: session)
            do {
                let solution = try SliderCaptchaSolver().solve(challenge)
                let payload = SliderVerificationPayload(solution: solution)
                let milliseconds = payload.tracks.reduce(0) { $0 + $1.c }
                // Keep elapsed challenge time consistent with the programmatic movement samples.
                try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
                try await verify(challenge, solution: solution, using: session)
                return solution
            } catch let error as SliderCaptchaError {
                switch error {
                case .noReliableMatch, .rejected:
                    lastError = error
                    if attempt + 1 == maxAttempts { throw error }
                default: throw error
                }
            }
        }
        throw lastError
    }

    private func request(path: String, body: Data? = nil, using session: URLSession) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
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
        canvasLength = solution.canvasLength
        moveLength = solution.moveLength
        let steps = max(12, min(55, Int(solution.moveLength / 3)))
        var points = [Point(a: 0, b: 0, c: 0)]
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            points.append(Point(a: solution.moveLength * progress,
                                b: sin(progress * .pi) * 2,
                                c: 24 + step % 5))
        }
        tracks = points
    }
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
