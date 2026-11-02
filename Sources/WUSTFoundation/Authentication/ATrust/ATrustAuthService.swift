import Foundation

public struct ATrustAuthService {
    let requestFactory = ATrustAuthRequestFactory()
    let callbackParser = ATrustCASCallbackParser()
    let responseValidator = ATrustResponseValidator()

    public init() {}
}
