import Foundation

struct ATrustAuthServer: Decodable {
    var authType: String
    var loginUrl: String
}
struct ATrustConfiguration: Decodable {
    var authServerInfoList: [ATrustAuthServer]
}
struct ATrustConfigurationResponse: Decodable {
    var code: Int
    var data: ATrustConfiguration?
}
