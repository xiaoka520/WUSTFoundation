import Foundation

extension UnionAuthService {
    public func availableVerificationMethods(
        for challenge: UnionVerificationChallenge,
        configuration: UnionLoginConfiguration
    ) throws -> [UnionVerificationMethod] {
        return try challengeParser.availableVerificationMethods(
            for: challenge,
            configuration: configuration
        )
    }

    public func sendSMSCode(
        username: String,
        challenge: UnionVerificationChallenge,
        configuration: UnionLoginConfiguration,
        using session: URLSession
    ) async throws {
        let methods = try availableVerificationMethods(
            for: challenge,
            configuration: configuration
        )

        guard methods.contains(.sms) else {
            throw UnionAuthServiceError.verificationMethodUnavailable
        }

        let request = try requestFactory.makeSMSCodeRequest(
            username: username,
            challenge: challenge
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnionAuthServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw UnionAuthServiceError.unexpectedStatusCode(
                httpResponse.statusCode
            )
        }
        let result = try JSONDecoder().decode(
            UnionSMSCodeResponse.self,
            from: data
        )
        guard result.meta.success else {
            throw UnionAuthServiceError.smsCodeRejected(
                result.meta.statusCode,
                result.meta.message ?? "服务器未提供错误说明"
            )
        }
        guard result.data == true else {
            throw UnionAuthServiceError.smsCodeNotConfirmed
        }

    }

    public func verifySMSCode(
        username: String,
        code: String,
        service: String,
        challenge: UnionVerificationChallenge,
        configuration: UnionLoginConfiguration,
        using session: URLSession
    ) async throws {
        let methods = try availableVerificationMethods(
            for: challenge,
            configuration: configuration
        )
        guard methods.contains(.sms) else {
            throw UnionAuthServiceError.verificationMethodUnavailable
        }
        let request = try requestFactory.makeSMSVerificationRequest(
            username: username,
            code: code,
            service: service,
            challenge: challenge
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnionAuthServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw
                UnionAuthServiceError
                .unexpectedStatusCode(httpResponse.statusCode)
        }
        let result = try JSONDecoder().decode(
            UnionSMSVerificationResponse.self,
            from: data
        )
        guard result.meta.success else {
            throw UnionAuthServiceError.smsVerificationRejected(
                result.meta.statusCode,
                result.meta.message ?? "服务器未提供错误说明"
            )
        }
        guard result.data?.flag == true else {
            throw UnionAuthServiceError.smsVerificationNotConfirmed
        }
    }
}
