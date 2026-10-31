import Foundation

extension UnionAuthService {
    public func fetchCaptcha(using session: URLSession) async throws
        -> LoginCaptcha
    {
        let request = try requestFactory.makeCaptchaRequest()

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnionAuthServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw UnionAuthServiceError.unexpectedStatusCode(
                httpResponse.statusCode
            )
        }
        return try JSONDecoder().decode(LoginCaptcha.self, from: data)
    }

    public func fetchLoginConfiguration(using session: URLSession) async throws
        -> UnionLoginConfiguration
    {
        let request = try requestFactory.makeLoginConfigurationRequest()

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
            UnionLoginConfigurationResponse.self,
            from: data
        )

        guard result.meta.success == true else {
            throw
                UnionAuthServiceError
                .configurationRejected(result.meta.statusCode)
        }

        guard let configuration = result.data else {
            throw UnionAuthServiceError.invalidResponse
        }

        return configuration
    }

    public func beginLogin(
        username: String,
        password: String,
        service: String,
        captcha: LoginCaptcha,
        captchaCode: String,
        using session: URLSession
    ) async throws -> UnionLoginResult {
        let encodedPassword = try UnionPasswordEncoder().encode(
            password: password
        )
        let parameters = LoginTicketParameters(
            username: username,
            encodedPassword: encodedPassword,
            service: service,
            captchaID: captcha.uid,
            captchaCode: captchaCode
        )
        return try await requestLogin(parameters: parameters, using: session)
    }

    private func requestLogin(
        parameters: LoginTicketParameters,
        using session: URLSession
    ) async throws -> UnionLoginResult {
        let request = try requestFactory.makeLoginRequest(
            parameters: parameters
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnionAuthServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw
                UnionAuthServiceError
                .unexpectedStatusCode(httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(
            LoginTicketResponse.self,
            from: data
        )
        //1. 需要二次验证
        if result.data?.code == "TWOVERIFY" {
            guard let info = result.data else {
                throw UnionAuthServiceError.invalidResponse
            }
            guard let uid = info.uid else {
                throw UnionAuthServiceError.invalidResponse
            }
            guard !uid.isEmpty else {
                throw UnionAuthServiceError.invalidResponse
            }
            guard let detailsJSON = info.data else {
                throw UnionAuthServiceError.invalidResponse
            }
            guard !detailsJSON.isEmpty else {
                throw UnionAuthServiceError.invalidResponse
            }
            _ = try challengeParser.parseDetails(from: detailsJSON)
            let challenge = UnionVerificationChallenge(
                uid: uid,
                detailsJSON: detailsJSON
            )
            return .verificationRequired(challenge)
        }
        if let tgt = result.tgt, !tgt.isEmpty {
            return .authenticated(UnionCredential(tgt: tgt))
        }
        //2.获得凭据
        if let credential = try extractCredential(from: httpResponse) {
            return .authenticated(credential)
        }
        //3.其他登录失败
        let code = result.data?.code ?? "UNKNOWN"
        throw UnionAuthServiceError.loginFailed(code)
    }

    private func extractCredential(from response: HTTPURLResponse) throws
        -> UnionCredential?
    {
        guard let url = response.url else {
            throw UnionAuthServiceError.invalidResponse
        }

        guard let headers = response.allHeaderFields as? [String: String] else {
            throw UnionAuthServiceError.invalidResponse
        }

        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: headers,
            for: url
        )

        for cookie in cookies {
            if cookie.name == "CASTGC" {
                guard !cookie.value.isEmpty else {
                    return nil
                }
                return UnionCredential(tgt: cookie.value)
            }
        }
        return nil
    }

    func requestServiceTicket(
        parameters: LoginTicketParameters,
        using session: URLSession
    ) async throws
        -> String
    {
        let request = try requestFactory.makeLoginRequest(
            parameters: parameters
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnionAuthServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UnionAuthServiceError.unexpectedStatusCode(
                httpResponse.statusCode
            )
        }

        let result = try JSONDecoder().decode(
            LoginTicketResponse.self,
            from: data
        )

        guard let ticket = result.ticket, !ticket.isEmpty else {
            let code = result.data?.code ?? "UNKNOWN"
            throw UnionAuthServiceError.loginFailed(code)
        }

        return ticket
    }

    func fetchServiceTicket(
        username: String,
        password: String,
        service: String,
        captcha: LoginCaptcha,
        captchaCode: String,
        using session: URLSession
    ) async throws -> String {
        let encodedPassword = try UnionPasswordEncoder().encode(
            password: password
        )
        let parameters = LoginTicketParameters(
            username: username,
            encodedPassword: encodedPassword,
            service: service,
            captchaID: captcha.uid,
            captchaCode: captchaCode
        )

        return try await requestServiceTicket(
            parameters: parameters,
            using: session
        )
    }
}
