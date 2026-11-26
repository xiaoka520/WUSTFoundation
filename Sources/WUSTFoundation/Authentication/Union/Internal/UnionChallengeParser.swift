import Foundation

struct UnionChallengeParser {
    func parseDetails(
        from detailsJSON: String
    ) throws -> [String: Any] {
        let data = Data(detailsJSON.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let details = object as? [String: Any] else {
            throw UnionAuthServiceError.invalidResponse
        }
        return details
    }

    // MARK: 返回可选的验证方式
    func availableVerificationMethods(
        for challenge: UnionVerificationChallenge,
        configuration: UnionLoginConfiguration
    ) throws -> [UnionVerificationMethod] {
        let details = try parseDetails(
            from: challenge.detailsJSON
        )

        var methods: [UnionVerificationMethod] = []

        for item in configuration.twoVerifyWay.split(separator: ",") {
            let code = String(item).trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            switch code {
            case "1":
                if let phone = details["phone"] as? String, !phone.isEmpty {
                    methods.append(.sms)
                }
            case "2":
                if let wechat = details["wechat"] as? String, !wechat.isEmpty {
                    methods.append(.wechat)
                }
            default:
                break
            }
        }
        return methods
    }
}
