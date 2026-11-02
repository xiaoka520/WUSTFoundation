import Foundation

extension ATrustAuthService {
    public func fetchCASLoginURL(using session: URLSession) async throws -> URL{
        let request = try requestFactory.makeConfigurationRequest(
            queryItems: [
                URLQueryItem(name: "needTicket", value: "1"),
                URLQueryItem(name: "mod", value: "1")
            ]
        )
        guard let configURL = request.url else {
            throw ATrustAuthServiceError.invalidURL
        }

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

        let request = requestFactory.makeCASLoginRequest(url: loginURL)

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

    func fetchCSRFToken(
        using session: URLSession
    ) async throws -> String {
        let request = try requestFactory.makeConfigurationRequest(
            queryItems: [URLQueryItem(name: "mod", value: "1")]
        )
        let (data, response) = try await session.data(for: request)
        _ = try responseValidator.validate(response, data: data, operation: "获取 CSRF Token")
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
}
