import Foundation

struct ATrustAuthServer: Decodable {
    var authType: String
    var loginUrl: String
}
struct ATrustConfiguration: Decodable {
    var authServerInfoList: [ATrustAuthServer]
    let security: ATrustSecurity?
}
struct ATrustConfigurationResponse: Decodable {
    var code: Int
    var data: ATrustConfiguration?
}
struct ATrustSecurity: Decodable {
    let csrfToken: String
}
