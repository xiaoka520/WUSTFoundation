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
}

public struct ATrustAuthService {
    public init() {}
    public func fetchCASLoginURL(using session: URLSession) async throws -> URL{
        var components = URLComponents()
        components.scheme = "https"
        components.host = "atrust.wust.edu.cn"
        components.path = "/passport/v1/public/authConfig"
        components.queryItems = [
            URLQueryItem(name: "needTicket", value: "1"),
            URLQueryItem(name: "mod", value: "1")
        ]
        
        guard let configURL = components.url else {
            throw ATrustAuthServiceError.invalidURL
        }
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
    
    private func exchangeCASTicket(
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
}
