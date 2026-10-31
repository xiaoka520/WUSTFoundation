struct UnionResponseMeta: Decodable {
    let success: Bool
    let statusCode: Int
    let message: String?
}
