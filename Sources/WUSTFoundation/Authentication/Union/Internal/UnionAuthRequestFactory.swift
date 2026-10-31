import Foundation

struct UnionAuthRequestFactory {
    let challengeParser = UnionChallengeParser()

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

    // MARK: 短信验证请求
    func makeSMSCodeRequest(
        username: String,
        challenge: UnionVerificationChallenge
    ) throws -> URLRequest {
        let details = try challengeParser.parseDetails(
            from: challenge.detailsJSON
        )
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
            "application/json;charset=utf-8",
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
        request.setValue(token, forHTTPHeaderField: "loginUserToken")
        request.setValue("loginToken", forHTTPHeaderField: "loginToken")

        let body: [String: String] = [
            "mobile": phone,
            "username": username,
            "module": "0"
        ]

        request.httpBody = try JSONSerialization.data(
            withJSONObject: body
        )

        return request
    }

    // MARK: 构造短信验证码请求
    func makeSMSVerificationRequest(
        username: String,
        code: String,
        service: String,
        challenge: UnionVerificationChallenge
    ) throws -> URLRequest {
        let details = try challengeParser.parseDetails(
            from: challenge.detailsJSON
        )
        guard let phone = details["phone"] as? String, !phone.isEmpty else {
            throw UnionAuthServiceError.verificationMethodUnavailable
        }
        guard let twoVerifyType = details["twoVerifyType"],
              !(twoVerifyType is NSNull) else {
            throw UnionAuthServiceError.invalidResponse
        }

        guard let url = URL(string: "https://auth.wust.edu.cn/lyuapServer/login/twoVertify") else {
            throw UnionAuthServiceError.invalidURL
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let token = try UnionPasswordEncoder().encode(password: "lyasp\(timestamp)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json;charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(token, forHTTPHeaderField: "token")
        request.setValue(token, forHTTPHeaderField: "loginUserToken")
        request.setValue("loginToken", forHTTPHeaderField: "loginToken")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(challenge.uid, forHTTPHeaderField: "vcodes")

        var body: [String: Any] = [
            "userName": username,
            "credential": code,
            "principal": phone,
            "type": "0",
            "service": service,
            "twoVerifyType": twoVerifyType,
            "loginType": "",
            "isCommonIP": (details["isCommonIP"] as? Bool == true) ? "0" : ""
        ]
        if let ext = details["ext"], !(ext is NSNull) {
            body["ext"] = ext
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return request
    }

    func makeCaptchaRequest() throws -> URLRequest {
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

        return request
    }

    func makeLoginConfigurationRequest() throws -> URLRequest {
        guard
            let url = URL(
                string: "https://auth.wust.edu.cn/lyuapServer/loginType"
            )
        else {
            throw UnionAuthServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        return request
    }

    func makeServiceTicketRequest(
        credential: UnionCredential,
        service: String
    ) throws -> URLRequest {
        guard let baseURL = URL(
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

        return request
    }
}
