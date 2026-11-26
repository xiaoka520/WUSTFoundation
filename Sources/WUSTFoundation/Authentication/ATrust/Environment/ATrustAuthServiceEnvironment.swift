import Foundation

extension ATrustAuthService {
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
        let request = try requestFactory.makeEnvironmentReportRequest(
            environmentTicket: environmentTicket,
            deviceID: deviceID,
            csrfToken: csrfToken
        )

        let (data, response) = try await session.data(for: request)
        _ = try responseValidator.validate(response, data: data, operation: "环境上报")
        let result = try JSONDecoder().decode(
            ATrustEnvironmentReportResponse.self,
            from: data
        )
        guard result.code == 0 else {
            throw ATrustAuthServiceError.rejected(result.code)
        }
    }
}
