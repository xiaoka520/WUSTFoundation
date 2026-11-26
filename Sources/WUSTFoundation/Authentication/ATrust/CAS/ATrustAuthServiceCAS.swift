import Foundation

extension ATrustAuthService {
    public func exchangeCASTicket(
        ticket: String,
        service: String,
        using session: URLSession
    ) async throws -> (Data, HTTPURLResponse) {
        let request = try requestFactory.makeCASTicketRequest(
            ticket: ticket,
            service: service
        )

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

    public func parseCASCallback(
        from url: URL
    ) throws -> ATrustCASCallbackResult {
        try callbackParser.parse(from: url)
    }
}
