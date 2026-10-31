struct UnionSMSVerificationResponse: Decodable {
    let meta: UnionResponseMeta
    let data: UnionSMSVerificationData?
}

struct UnionSMSVerificationData: Decodable {
    let flag: Bool?
}
