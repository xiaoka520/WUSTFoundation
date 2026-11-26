import Foundation

extension ATrustAuthService {
    @available(*, deprecated, message: "Use WUSTLoginClient for login and SMS continuation, or the credential-based API.")
    public func beginLogin(
        username: String,
        password: String,
        captcha: LoginCaptcha,
        captchaCode: String,
        using session: URLSession
    ) async throws -> (Data, HTTPURLResponse) {
        let service = try await fetchCASService(using: session)
        let ticket = try await UnionAuthService().fetchServiceTicket(
            username: username,
            password: password,
            service: service,
            captcha: captcha,
            captchaCode: captchaCode,
            using: session,
        )
        return try await exchangeCASTicket(
            ticket: ticket,
            service: service,
            using: session
        )

    }

    public func checkAuthentication(
        using session: URLSession
    ) async throws -> ATrustAuthenticationResult {
        let csrfToken = try await fetchCSRFToken(using: session)
        let request = try requestFactory.makeAuthenticationCheckRequest(csrfToken: csrfToken)
        guard let url = request.url else {
            throw ATrustAuthServiceError.invalidURL
        }
        let (data, response) = try await session.data(for: request)
        let httpResponse = try responseValidator.validate(response, data: data, operation: "authCheck")

        guard let finalURL = httpResponse.url,
              finalURL.scheme == url.scheme,
              finalURL.host == url.host,
              finalURL.path == url.path else {
            throw ATrustAuthServiceError.invalidRedirect
        }
        let result = try JSONDecoder().decode(
            ATrustAuthenticationResponse.self,
            from: data
        )
        guard result.code == 0 else {
            throw ATrustAuthServiceError.rejected(result.code)
        }
        guard let details = result.data else {
            throw ATrustAuthServiceError.invalidResponse
        }
        return ATrustAuthenticationResult(
            sidTicket: details.sidTicket,
            nextService: details.nextService
        )

    }

    public func completeLogin(
        ticket: String,
        service: String,
        deviceID: String,
        using session: URLSession
    ) async throws -> ATrustAuthenticationResult {
        let (_, response) = try await exchangeCASTicket(
            ticket: ticket,
            service: service,
            using: session
        )
        guard let url = response.url else {
            throw ATrustAuthServiceError.invalidResponse
        }
        let callback = try parseCASCallback(from: url)

        if let environmentTicket = callback.environmentTicket {
            try await reportEnvironment(
                environmentTicket: environmentTicket,
                deviceID: deviceID,
                using: session
            )
        }
        guard let nextService = callback.nextService, !nextService.isEmpty else {
            throw ATrustAuthServiceError.invalidRedirect
        }
        if nextService == "auth/authCheck" {
            return try await checkAuthentication(using: session)
        } else {
            return ATrustAuthenticationResult(
                sidTicket: nil,
                nextService: nextService
            )
        }
    }

    public func login(
        credential: UnionCredential,
        deviceID: String,
        using session: URLSession
    ) async throws -> ATrustAuthenticationResult {
        let service = try await fetchCASService(using: session)
        let ticket = try await UnionAuthService().fetchServiceTicket(
            credential: credential,
            service: service,
            using: session
        )
        return try await completeLogin(
            ticket: ticket,
            service: service,
            deviceID: deviceID,
            using: session
        )
    }
}
