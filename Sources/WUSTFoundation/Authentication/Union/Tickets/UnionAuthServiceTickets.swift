import Foundation

extension UnionAuthService {
    public func fetchServiceTicket(
        credential: UnionCredential,
        service: String,
        using session: URLSession
    ) async throws -> String {
        let request = try requestFactory.makeServiceTicketRequest(
            credential: credential,
            service: service
        )

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
}
