import Foundation

public enum UndergraduateAuthServiceError: Error {
    case invalidURL
    case invalidResponse
    case unexpectedStatusCode(Int)
    case cookieMissing
    case invalidEncoding //UTF-8解码失败
    case invalidSession //html.contains("script")
    case systemUnavailable //"禁用"
    case studentRecordNotFound //"不存在"
    case remoteSystemError //"500"
}

public struct UndergraduateAuthService {
    
    public init() {}
    
    private func exchangeTicket(ticket: String, using session: URLSession) async throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "bkjx.wust.edu.cn"
        components.path = "/jsxsd/"
        components.queryItems = [
            URLQueryItem(name: "ticket", value: ticket)
        ]
        
        guard let ticketURL = components.url else {
            throw UndergraduateAuthServiceError.invalidURL
        }
        
        guard let baseURL = URL(string: "https://bkjx.wust.edu.cn/jsxsd/") else {
            throw UndergraduateAuthServiceError.invalidURL
        }
        guard let studentInfoURL = URL(string: "https://bkjx.wust.edu.cn/jsxsd/grxx/xsxx") else {
            throw UndergraduateAuthServiceError.invalidURL
        }
        
        
        
        var ticketRequest = URLRequest(url: ticketURL)
        ticketRequest.httpMethod = "GET"
        var baseRequest = URLRequest(url: baseURL)
        baseRequest.httpMethod = "GET"
        
        let (_, ticketResponse) = try await session.data(for: ticketRequest)
        guard let ticketHttpResponse = ticketResponse as? HTTPURLResponse else {
            throw UndergraduateAuthServiceError.invalidResponse
        }
        guard (200..<300).contains(ticketHttpResponse.statusCode) else {
            throw UndergraduateAuthServiceError
                .unexpectedStatusCode(ticketHttpResponse.statusCode)
        }
        
        let (_, baseResponse) = try await session.data(for: baseRequest)
        guard let baseHttpResponse = baseResponse as? HTTPURLResponse else {
            throw UndergraduateAuthServiceError.invalidResponse
        }
        guard (200..<300).contains(baseHttpResponse.statusCode) else {
            throw UndergraduateAuthServiceError
                .unexpectedStatusCode(baseHttpResponse.statusCode)
        }
        
        try await validateSession(using: session)
        
        guard let studentInfoCookie = session.configuration.httpCookieStorage? .cookies(
            for: studentInfoURL
        ) else {
            throw UndergraduateAuthServiceError.cookieMissing
        }
        guard !studentInfoCookie.isEmpty else {
            throw UndergraduateAuthServiceError.cookieMissing
        }
        
        let headers = HTTPCookie.requestHeaderFields(with: studentInfoCookie)
        
        guard let cookie = headers["Cookie"], !cookie.isEmpty else {
            throw UndergraduateAuthServiceError.cookieMissing
        }
        return cookie
    }
    
    public func login(
        username: String,
        password: String,
        captcha: LoginCaptcha,
        captchaCode: String,
        using session: URLSession
    ) async throws -> String {
        let service = "https://bkjx.wust.edu.cn/jsxsd/"
        let ticket = try await UnionAuthService().fetchServiceTicket(
            username: username,
            password: password,
            service: service,
            captcha: captcha,
            captchaCode: captchaCode,
            using: session
        )
        
        let cookie = try await exchangeTicket(ticket: ticket, using: session)
        return cookie
    }
    
    private func validateSession(using session: URLSession) async throws {
        guard let url = URL(string: "https://bkjx.wust.edu.cn/jsxsd/framework/blankPage.jsp") else {
            throw UndergraduateAuthServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpRespnse = response as? HTTPURLResponse else {
            throw UndergraduateAuthServiceError.invalidResponse
        }
        guard httpRespnse.statusCode == 200 else {
            throw UndergraduateAuthServiceError.unexpectedStatusCode(httpRespnse.statusCode)
        }
        
        if data.count < 8 {
            return
        } else {
            guard let html = String(data: data, encoding: .utf8) else {
                throw UndergraduateAuthServiceError.invalidEncoding
            }
            guard !html.contains("script") else {
                throw UndergraduateAuthServiceError.invalidSession
            }
            guard !html.contains("禁用") else {
                throw UndergraduateAuthServiceError.systemUnavailable
            }
            guard !html.contains("不存在") else {
                throw UndergraduateAuthServiceError.studentRecordNotFound
            }
            guard !html.contains("500") else {
                throw UndergraduateAuthServiceError.remoteSystemError
            }
        }
    }
    
    public func login(
        credential: UnionCredential,
        using session: URLSession
    ) async throws -> String {
        let service = "https://bkjx.wust.edu.cn/jsxsd/"
        let ticket = try await UnionAuthService().fetchServiceTicket(
            credential: credential,
            service: service,
            using: session
        )
        return try await exchangeTicket(
            ticket: ticket,
            using: session
        )
        
    }
}
