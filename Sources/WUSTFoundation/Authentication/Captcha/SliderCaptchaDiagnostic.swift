import Foundation

/// Optional numeric diagnostics. Never includes challenge images, keys, credentials or cookie values.
public enum SliderCaptchaDiagnostic: Sendable {
    public enum Phase: String, Sendable {
        case session, fetch, decode, matching, preparing, waiting, verification
    }
    case phase(Phase)
    case request(endpoint: String, cookieCount: Int)
    case requestProfile(name: String)
    case httpResponse(endpoint: String, status: Int, expectedHost: Bool, cookieCount: Int)
    case challenge(backgroundBytes: Int, pieceBytes: Int, tagWidth: Int, yHeight: Int)
    case match(pixelOffset: Int, moveLength: Double, confidence: Double)
    case candidates(pixelOffset: Int, bestScore: Double, alternativeScore: Double)
    case matchingRejected(reason: String)
    case challengeDiscarded(count: Int, limit: Int)
    case trajectory(points: Int, durationMilliseconds: Int, verticalMin: Double, verticalMax: Double)
    case trajectoryPoints(SliderCaptchaTrace)
    case result(code: Int)
    case failure(kind: String)
}
