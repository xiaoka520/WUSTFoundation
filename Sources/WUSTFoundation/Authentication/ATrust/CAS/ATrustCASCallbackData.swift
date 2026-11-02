// MARK: 解析data参数

struct ATrustEnvironmentRequirement: Decodable {
    let need: Bool
}

struct ATrustCASCallbackData: Decodable {
    let env: ATrustEnvironmentRequirement?
    let ticket: String?
}
