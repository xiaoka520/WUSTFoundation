struct ATrustAuthenticationData: Decodable {
    let sidTicket: String?
    let nextService: String?
}

struct ATrustAuthenticationResponse: Decodable {
    let code: Int
    let message: String?
    let data: ATrustAuthenticationData?
}
