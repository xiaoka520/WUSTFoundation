public struct UnionCredential: Sendable {
    public let tgt: String

    public init(tgt: String) {
        self.tgt = tgt
    }
}
