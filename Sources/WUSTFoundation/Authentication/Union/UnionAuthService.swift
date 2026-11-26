import Foundation

public struct UnionAuthService {
    let requestFactory = UnionAuthRequestFactory()
    let challengeParser = UnionChallengeParser()

    public init() {}
}
