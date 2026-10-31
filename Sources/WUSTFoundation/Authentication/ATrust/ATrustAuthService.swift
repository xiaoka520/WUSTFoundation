import Foundation

public enum ATrustAuthServiceError: Error {
    case invalidURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case rejected(Int)
    case invalidConfiguration
    case casLoginNotFound
    case invalidRedirect
    case serviceNotFound
    case requestFailed(operation: String, statusCode: Int, businessCode: Int?)
    case invalidEnvironmentTicket
    case invalidDeviceID
}

public struct ATrustAuthService {
    public init() {}
    public func fetchCASLoginURL(using session: URLSession) async throws -> URL{
        let configURL = try makeRequestURL(
            path: "/passport/v1/public/authConfig",
            queryItems: [
                URLQueryItem(name: "needTicket", value: "1"),
                URLQueryItem(name: "mod", value: "1")
            ]
        )
        var request = URLRequest(url: configURL)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ATrustAuthServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw ATrustAuthServiceError
                .unexpectedStatusCode(httpResponse.statusCode)
        }
        
        let result = try JSONDecoder().decode(
            ATrustConfigurationResponse.self,
            from: data
        )
        guard result.code == 0 else {
            throw ATrustAuthServiceError.rejected(result.code)
        }
        
        guard let configuration = result.data else {
            throw ATrustAuthServiceError.invalidConfiguration
        }
        
        for server in configuration.authServerInfoList {
            if server.authType == "auth/cas" {
                guard let url = URL(
                    string: server.loginUrl,
                    relativeTo: configURL
                )?.absoluteURL else {
                    throw ATrustAuthServiceError.invalidURL
                }
                return url
            }
        }
        throw ATrustAuthServiceError.casLoginNotFound
    }
    public func fetchCASService(using session: URLSession) async throws -> String {
        let loginURL = try await fetchCASLoginURL(using: session)
        
        var request = URLRequest(url: loginURL)
        request.httpMethod = "GET"
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ATrustAuthServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw ATrustAuthServiceError
                .unexpectedStatusCode(httpResponse.statusCode)
        }
        
        guard let finalURL = httpResponse.url else {
            throw ATrustAuthServiceError.invalidRedirect
        }
        guard finalURL.host == "auth.wust.edu.cn" && finalURL.path == "/lyuapServer/login" else {
            throw ATrustAuthServiceError.invalidRedirect
        }
        
        guard let components = URLComponents(
            url: finalURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw ATrustAuthServiceError.invalidRedirect
        }
        
        guard let queryItems = components.queryItems else {
            throw ATrustAuthServiceError.serviceNotFound
        }
        
        for item in queryItems {
            if item.name == "service" {
                guard let value = item.value else {
                    throw ATrustAuthServiceError.serviceNotFound
                }
                guard !value.isEmpty else {
                    throw ATrustAuthServiceError.serviceNotFound
                }
                return value
            }
        }
        throw ATrustAuthServiceError.serviceNotFound
    }
    
    public func exchangeCASTicket(
        ticket: String,
        service: String,
        using session: URLSession
    ) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(string: service) else {
            throw ATrustAuthServiceError.invalidURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "ticket", value: ticket))
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw ATrustAuthServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ATrustAuthServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ATrustAuthServiceError
                .unexpectedStatusCode(httpResponse.statusCode)
        }
        
        return (data, httpResponse)
    }
    
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

    private func fetchCSRFToken(
        using session: URLSession
    ) async throws -> String {
        let url = try makeRequestURL(
            path: "/passport/v1/public/authConfig",
            queryItems: [URLQueryItem(name: "mod", value: "1")]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        _ = try validateResponse(response, data: data, operation: "获取 CSRF Token")
        let result = try JSONDecoder().decode(
            ATrustConfigurationResponse.self,
            from: data
        )
        guard result.code == 0 else {
            throw ATrustAuthServiceError.rejected(result.code)
        }
        guard let csrfToken = result.data?.security?.csrfToken,
              !csrfToken.isEmpty else {
            throw ATrustAuthServiceError.invalidConfiguration
        }

        return csrfToken
    }

    public func checkAuthentication(
        using session: URLSession
    ) async throws -> (Data, HTTPURLResponse) {
        let csrfToken = try await fetchCSRFToken(using: session)
        let url = try makeRequestURL(path: "/passport/v1/auth/authCheck")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let traceID = String(UUID().uuidString.prefix(8)).lowercased()

        request.setValue(csrfToken, forHTTPHeaderField: "x-csrf-token")
        request.setValue(traceID, forHTTPHeaderField: "x-sdp-traceid")
        let (data, response) = try await session.data(for: request)
        let httpResponse = try validateResponse(response, data: data, operation: "authCheck")
        return (data, httpResponse)
    }

    private func makeRequestURL(
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        #if os(macOS) || targetEnvironment(macCatalyst)
        let platform = "Mac"
        #elseif os(iOS)
        let platform = "iOS"
        #else
        let platform = "Unknown"
        #endif

        var components = URLComponents()
        components.scheme = "https"
        components.host = "atrust.wust.edu.cn"
        components.path = path
        components.queryItems = queryItems + [
            URLQueryItem(name: "clientType", value: "SDPBrowserClient"),
            URLQueryItem(name: "platform", value: platform),
            URLQueryItem(name: "lang", value: "zh-CN")
        ]
        guard let url = components.url else {
            throw ATrustAuthServiceError.invalidURL
        }
        return url
    }

    private func validateResponse(
        _ response: URLResponse,
        data: Data,
        operation: String
    ) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ATrustAuthServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw ATrustAuthServiceError.requestFailed(
                operation: operation,
                statusCode: httpResponse.statusCode,
                businessCode: object?["code"] as? Int
            )
        }
        return httpResponse
    }

    
    public func reportEnvironment(
        environmentTicket: String,
        deviceID: String,
        using session: URLSession
    ) async throws {
        guard !environmentTicket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ATrustAuthServiceError.invalidEnvironmentTicket
        }
        guard !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ATrustAuthServiceError.invalidDeviceID
        }
        let csrfToken = try await fetchCSRFToken(using: session)
        let url = try makeRequestURL(
            path: "/controller/v1/public/reportEnv"
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(csrfToken, forHTTPHeaderField: "x-csrf-token")
        let traceID = String(UUID().uuidString.prefix(8)).lowercased()
        request.setValue(traceID, forHTTPHeaderField: "x-sdp-traceid")

        let payload: [String: Any] = [
            "ticket": environmentTicket,
            "deviceId": deviceID,
            "env": [
                "endpoint": [
                    "device_id": deviceID,
                    "device": ["type": "browser"]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        _ = try validateResponse(response, data: data, operation: "环境上报")
        let result = try JSONDecoder().decode(
            ATrustEnvironmentReportResponse.self,
            from: data
        )
        guard result.code == 0 else {
            throw ATrustAuthServiceError.rejected(result.code)
        }
    }
}
