import Foundation

struct ATrustResponseValidator {
    func validate(
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
}
