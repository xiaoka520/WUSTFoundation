import Foundation


public actor WUSTLoginClient {
    public typealias CaptchaSolver = @Sendable (LoginCaptcha) async throws -> String

    private let username: String
    private let deviceID: String
    private let store: (any UnionCredentialStore)?
    private let configuration: URLSessionConfiguration
    private let solver: CaptchaSolver
    private let maxCaptchaAttempts: Int
    private var session: URLSession
    private var credential: UnionCredential?
    private var loadedCredential = false
    private var pending: PendingVerification?
    private var version = 0
    private var undergraduateSessionRevision = 0
    private var undergraduateSessionNeedsRefresh = false
    private var loggingOut = false
    private var operation: (id: UUID, kind: OperationKind, task: Task<WUSTLoginResult, Error>)?

    private enum OperationKind { case restore, refresh, login, verification }
    private struct PendingVerification {
        let challenge: UnionVerificationChallenge
        let configuration: UnionLoginConfiguration
        let methods: [UnionVerificationMethod]
        let service: String
    }

    public init(
        username: String,
        deviceID: String,
        credential: UnionCredential? = nil,
        credentialStore: (any UnionCredentialStore)? = nil,
        sessionConfiguration: URLSessionConfiguration = .ephemeral,
        maxCaptchaAttempts: Int = 3,
        captchaSolver: CaptchaSolver? = nil
    ) throws {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              maxCaptchaAttempts > 0 else {
            throw WUSTLoginClientError.invalidConfiguration
        }
        self.username = username
        self.deviceID = deviceID
        self.credential = credential
        self.store = credentialStore
        self.configuration = (sessionConfiguration.copy() as? URLSessionConfiguration) ?? .ephemeral
        self.session = Self.makeSession(configuration: sessionConfiguration)
        self.maxCaptchaAttempts = maxCaptchaAttempts
        self.solver = captchaSolver ?? { captcha in try Self.recognizeCaptcha(captcha) }
    }

    deinit { session.invalidateAndCancel() }


    public func ensureSession() async throws -> WUSTLoginResult {
        try await run(kind: .restore) { try await self.restore() }
    }


    public func login(password: String) async throws -> WUSTLoginResult {
        try await run(kind: .login) { try await self.performLogin(password: password) }
    }


    public func sendSMSCode() async throws {
        _ = try await run(kind: .verification) { try await self.performSendSMS() }
    }


    public func submitSMSCode(_ code: String, password: String) async throws -> WUSTLoginResult {
        try await run(kind: .verification) {
            try await self.performSubmitSMS(code, password: password)
        }
    }


    public func currentCredential() -> UnionCredential? { credential }


    public func fetchStudentInfo() async throws -> StudentInfo {
        let expectedVersion = version
        let info = try await withUndergraduateSession { cookie, session in
            try await StudentInfoService().fetchStudentInfo(cookie: cookie, using: session)
        }
        try checkActive(expectedVersion)
        guard info.studentID == username else {
            try await logout()
            throw WUSTLoginClientError.studentIDMismatch
        }
        return info
    }

    func withUndergraduateSession<Value: Sendable>(
        retryOnAuthenticationFailure shouldRetry: @Sendable (any Error) -> Bool = { _ in false },
        perform request: @Sendable (String, URLSession) async throws -> Value
    ) async throws -> Value {
        let expectedVersion = version
        let result = try await ensureSession()
        guard case .authenticated(let initialCookie) = result else {
            throw WUSTLoginClientError.notAuthenticated
        }
        try checkActive(expectedVersion)

        var cookie = initialCookie
        var canRetry = true
        while true {
            let sessionRevision = undergraduateSessionRevision
            do {
                let value = try await request(cookie, session)
                try checkActive(expectedVersion)
                return value
            } catch {
                try checkActive(expectedVersion)
                guard canRetry, shouldRetry(error) else {
                    throw error
                }
            }

            canRetry = false
            let restored = try await refreshSession(
                after: sessionRevision,
                expectedVersion: expectedVersion
            )
            guard case .authenticated(let restoredCookie) = restored else {
                throw WUSTLoginClientError.notAuthenticated
            }
            try checkActive(expectedVersion)
            cookie = restoredCookie
        }
    }

    private func refreshSession(
        after failedRevision: Int,
        expectedVersion: Int
    ) async throws -> WUSTLoginResult {
        try checkActive(expectedVersion)
        if let active = operation {
            guard active.kind == .restore || active.kind == .refresh else {
                throw WUSTLoginClientError.operationInProgress
            }
            let result = try await active.task.value
            if operation?.id == active.id { operation = nil }
            guard case .authenticated = result else { return result }
            try checkActive(expectedVersion)
        }
        if undergraduateSessionRevision != failedRevision {
            return try await ensureSession()
        }
        return try await run(kind: .refresh) {
            try await self.restore(forceRefresh: true)
        }
    }

    public func logout() async throws {
        guard !loggingOut else { throw WUSTLoginClientError.operationInProgress }
        loggingOut = true
        defer { loggingOut = false }
        version += 1
        let task = operation?.task
        operation = nil
        task?.cancel()
        session.invalidateAndCancel()
        credential = nil
        loadedCredential = true
        pending = nil
        undergraduateSessionNeedsRefresh = false
        session = Self.makeSession(configuration: configuration)
        if let task { _ = await task.result }
        try await store?.clearCredential(for: username)
    }

    private func run(
        kind: OperationKind,
        body: @escaping @Sendable () async throws -> WUSTLoginResult
    ) async throws -> WUSTLoginResult {
        guard !loggingOut else { throw WUSTLoginClientError.operationInProgress }
        if let active = operation {
            let canShare = kind == .restore && (active.kind == .restore || active.kind == .refresh)
                || kind == .refresh && active.kind == .refresh
            guard canShare else {
                throw WUSTLoginClientError.operationInProgress
            }
            return try await active.task.value
        }
        let id = UUID()
        let task = Task { try await body() }
        operation = (id, kind, task)
        defer { if operation?.id == id { operation = nil } }
        return try await task.value
    }

    private func restore(forceRefresh: Bool = false) async throws -> WUSTLoginResult {
        let expectedVersion = version
        if forceRefresh { undergraduateSessionNeedsRefresh = true }
        if let pending {
            return .verificationRequired(pending.challenge, methods: pending.methods)
        }
        if !undergraduateSessionNeedsRefresh {
            do {
                let cookie = try await UndergraduateAuthService().currentSessionCookie(using: session)
                try checkActive(expectedVersion)
                return .authenticated(cookie: cookie)
            } catch UndergraduateAuthServiceError.cookieMissing {
            } catch UndergraduateAuthServiceError.invalidSession {}
        }

        if credential == nil, !loadedCredential {
            let saved = try await store?.loadCredential(for: username)
            try checkActive(expectedVersion)
            credential = saved
            loadedCredential = true
        }
        guard let credential else { return .loginRequired }
        do {
            let result = try await ATrustAuthService().login(
                credential: credential, deviceID: deviceID, using: session
            )
            try checkActive(expectedVersion)
            guard result.isAuthenticated else {
                return .additionalAuthenticationRequired(nextService: result.nextService)
            }
            return try await establishUndergraduateSession(credential, expectedVersion: expectedVersion)
        } catch UnionAuthServiceError.credentialExpired {
            try checkActive(expectedVersion)
            return try await forgetExpiredCredential()
        }
    }

    private func performLogin(password: String) async throws -> WUSTLoginResult {
        guard !password.isEmpty else { throw WUSTLoginClientError.invalidConfiguration }
        version += 1
        let expectedVersion = version
        session.invalidateAndCancel()
        session = Self.makeSession(configuration: configuration)
        undergraduateSessionNeedsRefresh = false
        pending = nil
        credential = nil
        loadedCredential = true
        try await store?.clearCredential(for: username)
        try checkActive(expectedVersion)
        let service = try await ATrustAuthService().fetchCASService(using: session)
        try checkActive(expectedVersion)
        return try await authenticate(password: password, service: service, expectedVersion: expectedVersion)
    }

    private func authenticate(password: String, service: String, expectedVersion: Int) async throws -> WUSTLoginResult {
        let union = UnionAuthService()
        let (captcha, answer) = try await recognizedCaptcha(expectedVersion: expectedVersion)
        let result = try await union.beginLogin(
            username: username, password: password, service: service,
            captcha: captcha, captchaCode: answer, using: session
        )
        try checkActive(expectedVersion)
        switch result {
        case .verificationRequired(let challenge):
            pending = nil
            let config = try await union.fetchLoginConfiguration(using: session)
            try checkActive(expectedVersion)
            let methods = try union.availableVerificationMethods(for: challenge, configuration: config)
            pending = PendingVerification(challenge: challenge, configuration: config, methods: methods, service: service)
            return .verificationRequired(challenge, methods: methods)
        case .authenticated(let credential):
            pending = nil
            self.credential = credential
            try await store?.saveCredential(credential, for: username)
            try checkActive(expectedVersion)
            do {
                let ticket = try await union.fetchServiceTicket(credential: credential, service: service, using: session)
                try checkActive(expectedVersion)
                let result = try await ATrustAuthService().completeLogin(
                    ticket: ticket, service: service, deviceID: deviceID, using: session
                )
                try checkActive(expectedVersion)
                guard result.isAuthenticated else {
                    return .additionalAuthenticationRequired(nextService: result.nextService)
                }
                return try await establishUndergraduateSession(credential, expectedVersion: expectedVersion)
            } catch UnionAuthServiceError.credentialExpired {
                try checkActive(expectedVersion)
                return try await forgetExpiredCredential()
            }
        }
    }

    private func performSendSMS() async throws -> WUSTLoginResult {
        guard let pending else { throw WUSTLoginClientError.verificationNotPending }
        let expectedVersion = version
        try await UnionAuthService().sendSMSCode(
            username: username, challenge: pending.challenge, configuration: pending.configuration, using: session
        )
        try checkActive(expectedVersion)
        return .verificationRequired(pending.challenge, methods: pending.methods)
    }

    private func performSubmitSMS(_ code: String, password: String) async throws -> WUSTLoginResult {
        guard let pending else { throw WUSTLoginClientError.verificationNotPending }
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            throw WUSTLoginClientError.invalidConfiguration
        }
        let expectedVersion = version
        try await UnionAuthService().verifySMSCode(
            username: username, code: code, service: pending.service,
            challenge: pending.challenge, configuration: pending.configuration, using: session
        )
        try checkActive(expectedVersion)
        self.pending = nil
        return try await authenticate(password: password, service: pending.service, expectedVersion: expectedVersion)
    }

    private func recognizedCaptcha(expectedVersion: Int) async throws -> (LoginCaptcha, String) {
        for _ in 0..<maxCaptchaAttempts {
            let captcha = try await UnionAuthService().fetchCaptcha(using: session)
            try checkActive(expectedVersion)
            do {
                let answer = try await solver(captcha)
                try checkActive(expectedVersion)
                return (captcha, answer)
            } catch is CaptchaRecognitionError {
            }
        }
        throw WUSTLoginClientError.captchaRecognitionExhausted
    }

    private func establishUndergraduateSession(_ credential: UnionCredential, expectedVersion: Int) async throws -> WUSTLoginResult {
        let cookie = try await UndergraduateAuthService().login(credential: credential, using: session)
        try checkActive(expectedVersion)
        undergraduateSessionRevision += 1
        undergraduateSessionNeedsRefresh = false
        return .authenticated(cookie: cookie)
    }

    private func forgetExpiredCredential() async throws -> WUSTLoginResult {
        version += 1
        let expectedVersion = version
        credential = nil
        pending = nil
        session.invalidateAndCancel()
        session = Self.makeSession(configuration: configuration)
        undergraduateSessionNeedsRefresh = false
        try await store?.clearCredential(for: username)
        try checkActive(expectedVersion)
        return .loginRequired
    }

    private func checkActive(_ expectedVersion: Int) throws {
        try Task.checkCancellation()
        guard version == expectedVersion, !loggingOut else { throw CancellationError() }
    }

    private nonisolated static func makeSession(configuration: URLSessionConfiguration) -> URLSession {
        let copy = (configuration.copy() as? URLSessionConfiguration) ?? .ephemeral
        copy.httpCookieStorage = URLSessionConfiguration.ephemeral.httpCookieStorage
        copy.urlCache = nil
        return URLSession(configuration: copy)
    }

    private nonisolated static func recognizeCaptcha(_ captcha: LoginCaptcha) throws -> String {
        let parts = captcha.content.split(separator: ",", maxSplits: 1)
        let encoded = parts.count == 2 ? String(parts[1]) : captcha.content
        guard let data = Data(base64Encoded: encoded) else { throw WUSTLoginClientError.invalidCaptchaImage }
        return try VisionCaptchaSolver().solve(imageData: data)
    }
}
