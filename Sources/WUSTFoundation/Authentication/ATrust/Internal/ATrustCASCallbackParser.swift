import Foundation

struct ATrustCASCallbackParser {
    func parse(
        from url: URL
    ) throws -> ATrustCASCallbackResult {
        guard url.scheme == "https",
              url.host == "atrust.wust.edu.cn",
              url.path == "/portal/shortcut.html" else {
            throw ATrustAuthServiceError.invalidRedirect
        }
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            throw ATrustAuthServiceError.invalidRedirect
        }
        let queryItems = components.queryItems ?? []
        let isCommonError = queryItems.contains {
            $0.name == "type" && $0.value == "common_error"
        }
        let hasErrorInfo = queryItems.contains {
            $0.name == "err_info" && !($0.value ?? "").isEmpty
        }

        guard !isCommonError, !hasErrorInfo else {
            throw ATrustAuthServiceError.casCallbackRejected
        }
        let dataItems = queryItems.filter { $0.name == "data" }
        let nextServiceItems = queryItems.filter { $0.name == "nextService" }

        guard dataItems.count <= 1,
              nextServiceItems.count <= 1 else {
            throw ATrustAuthServiceError.invalidRedirect
        }
        var environmentTicket: String? = nil
        if let value = dataItems.first?.value, !value.isEmpty {
            let payload = try JSONDecoder().decode(
                ATrustCASCallbackData.self,
                from: Data(value.utf8)
            )
            if payload.env?.need == true {
                guard let ticket = payload.ticket,
                      !ticket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ATrustAuthServiceError.invalidEnvironmentTicket
                }
                environmentTicket = ticket
            }
        }

        return ATrustCASCallbackResult(
            environmentTicket: environmentTicket,
            nextService: nextServiceItems.first?.value
        )
    }
}
