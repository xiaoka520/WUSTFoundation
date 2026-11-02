import Foundation

struct ATrustAuthRequestFactory {
    func makeConfigurationRequest(queryItems: [URLQueryItem] = []) throws -> URLRequest {
        let url = try makeRequestURL(
            path: "/passport/v1/public/authConfig",
            queryItems: queryItems
        )
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }

    func makeCASLoginRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }

    func makeCASTicketRequest(ticket: String, service: String) throws -> URLRequest {
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
        return request
    }

    func makeAuthenticationCheckRequest(csrfToken: String) throws -> URLRequest {
        let url = try makeRequestURL(path: "/passport/v1/auth/authCheck")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let traceID = String(UUID().uuidString.prefix(8)).lowercased()
        request.setValue(csrfToken, forHTTPHeaderField: "x-csrf-token")
        request.setValue(traceID, forHTTPHeaderField: "x-sdp-traceid")
        return request
    }

    func makeEnvironmentReportRequest(
        environmentTicket: String,
        deviceID: String,
        csrfToken: String
    ) throws -> URLRequest {
        let url = try makeRequestURL(path: "/controller/v1/public/reportEnv")
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
        return request
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
}
