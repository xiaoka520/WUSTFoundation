import Foundation

public enum UnionAuthServiceError: Error {
    case invalidURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case invalidFormEncoding
    case loginFailed(String)
    case configurationRejected(Int)
    case credentialExpired
    case verificationMethodUnavailable
    case smsCodeRejected(Int)
    case smsCodeNotConfirmed
}

public struct UnionAuthService {

    public init() {}

    // MARK: 获取人机验证
    public func fetchCaptcha(using session: URLSession) async throws
        -> LoginCaptcha
    {
        let timestamp = Int(Date().timeIntervalSince1970)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "auth.wust.edu.cn"
        components.path = "/lyuapServer/kaptcha"
        components.queryItems = [
            URLQueryItem(name: "_t", value: String(timestamp)),
            URLQueryItem(name: "uid", value: ""),
        ]
        guard let url = components.url else {
            throw UnionAuthServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

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
    // MARK: 构造登录请求
    func makeLoginRequest(parameters: LoginTicketParameters) throws
        -> URLRequest
    {
        guard
            let url = URL(
                string: "https://auth.wust.edu.cn/lyuapServer/v1/tickets"
            )
        else {
            throw UnionAuthServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "username", value: parameters.username),
            URLQueryItem(name: "password", value: parameters.encodedPassword),
            URLQueryItem(name: "service", value: parameters.service),
            URLQueryItem(name: "loginType", value: ""),
            URLQueryItem(name: "id", value: parameters.captchaID),
            URLQueryItem(name: "code", value: parameters.captchaCode),
        ]

        guard let query = form.percentEncodedQuery else {
            throw UnionAuthServiceError.invalidFormEncoding
        }

        let body = query.replacingOccurrences(of: "+", with: "%2B")
        request.httpBody = Data(body.utf8)

        return request
    }
    // MARK: 请求凭证
    func requestServiceTicket(
        parameters: LoginTicketParameters,
        using session: URLSession
    ) async throws
        -> String
    {
        let request = try makeLoginRequest(parameters: parameters)
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
    public func fetchLoginConfiguration(using session: URLSession) async throws
        -> UnionLoginConfiguration
    {
        guard
            let url = URL(
                string: "https://auth.wust.edu.cn/lyuapServer/loginType"
            )
        else {
            throw UnionAuthServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
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
    public func fetchServiceTicket(
        credential: UnionCredential,
        service: String,
        using session: URLSession
    ) async throws -> String {
        guard
            let baseURL = URL(
                string: "https://auth.wust.edu.cn/lyuapServer/v1/tickets"
            )
        else {
            throw UnionAuthServiceError.invalidURL
        }

        let url = baseURL.appendingPathComponent(credential.tgt)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "service", value: service),
            URLQueryItem(name: "loginToken", value: "loginToken"),
        ]

        guard let query = form.percentEncodedQuery else {
            throw UnionAuthServiceError.invalidFormEncoding
        }
        let body = query.replacingOccurrences(of: "+", with: "%2B")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnionAuthServiceError.invalidResponse
        }
        guard
            let ticket = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw UnionAuthServiceError.invalidResponse
        }
        if httpResponse.statusCode == 500 && ticket.hasPrefix("TGT :") {
            throw UnionAuthServiceError.credentialExpired
        }
        guard httpResponse.statusCode == 200 else {
            throw
                UnionAuthServiceError
                .unexpectedStatusCode(httpResponse.statusCode)
        }
        guard ticket.hasPrefix("ST-") else {
            throw UnionAuthServiceError.invalidResponse
        }
        return ticket
    }

    private func requestLogin(
        parameters: LoginTicketParameters,
        using session: URLSession
    ) async throws -> UnionLoginResult {
        let request = try makeLoginRequest(parameters: parameters)
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
            guard
                (try JSONSerialization.jsonObject(
                    with: Data(detailsJSON.utf8)
                ) as? [String: Any]) != nil
            else {
                throw UnionAuthServiceError.invalidResponse
            }
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
    // MARK: 返回可选的验证方式
    public func availableVerificationMethods(
        for challenge: UnionVerificationChallenge,
        configuration: UnionLoginConfiguration
    ) throws -> [UnionVerificationMethod] {
        let data = try JSONSerialization.jsonObject(
            with: Data(challenge.detailsJSON.utf8)
        )
        guard let details = data as? [String: Any] else {
            throw UnionAuthServiceError.invalidResponse
        }

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
    // MARK: 短信验证请求
    private func makeSMSCodeRequest(
        username: String,
        challenge: UnionVerificationChallenge
    ) throws -> URLRequest {
        guard
            let details = try JSONSerialization.jsonObject(
                with: Data(challenge.detailsJSON.utf8)
            ) as? [String: Any]
        else {
            throw UnionAuthServiceError.invalidResponse
        }
        guard let phone = details["phone"] as? String, !phone.isEmpty else {
            throw UnionAuthServiceError.verificationMethodUnavailable
        }

        guard
            let url = URL(
                string:
                    "https://auth.wust.edu.cn/lyuapServer/login/mobile/generateCode"
            )
        else {
            throw UnionAuthServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "XMLHttpRequest",
            forHTTPHeaderField: "X-Requested-With"
        )
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let token = try UnionPasswordEncoder().encode(
            password: "lyasp\(timestamp)"
        )
        request.setValue(token, forHTTPHeaderField: "token")
        
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "mobile", value: phone),
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "module", value: "0")
        ]
        guard let query = form.percentEncodedQuery else {
            throw UnionAuthServiceError.invalidFormEncoding
        }
        let body = query.replacingOccurrences(of: "+", with: "%2B")
        request.httpBody = Data(body.utf8)
        
        return request
    }
    // MARK: 发送短信验证码
    public func sendSMSCode(
        username: String,
        challenge: UnionVerificationChallenge,
        configuration: UnionLoginConfiguration,
        using session: URLSession
    ) async throws {
        let methods = try availableVerificationMethods(
            for: challenge,
            configuration: configuration)
        
        guard methods.contains(.sms) else {
            throw UnionAuthServiceError.verificationMethodUnavailable
        }
        
        let request = try makeSMSCodeRequest(username: username, challenge: challenge)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnionAuthServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw UnionAuthServiceError.unexpectedStatusCode(httpResponse.statusCode)
        }
        let result = try JSONDecoder().decode(
            UnionSMSCodeResponse.self,
            from: data
        )
        guard result.meta.success == true else {
            throw UnionAuthServiceError.smsCodeRejected(result.meta.statusCode)
        }
        guard result.data == true else {
            throw UnionAuthServiceError.smsCodeNotConfirmed
        }
        
    }
    
}
