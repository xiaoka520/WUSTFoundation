import Foundation

public actor WUSTLoginClient {
    private let username: String
    private let configuration: URLSessionConfiguration
    private var session: URLSession
    private var pendingSMSLogin: (context: AuthServerSMSLoginContext, session: URLSession)?
    private var pendingManualLogin: ManualSliderCaptchaSession?
    private var version = 0
    private var sessionInvalidated = false
    private var loggingOut = false
    private var operation: (id: UUID, kind: OperationKind, task: Task<WUSTLoginResult, Error>)?

    private enum OperationKind { case check, login }

    public init(username: String, sessionConfiguration: URLSessionConfiguration = .ephemeral) throws {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WUSTLoginClientError.invalidConfiguration
        }
        self.username = username
        self.configuration = (sessionConfiguration.copy() as? URLSessionConfiguration) ?? .ephemeral
        self.session = Self.makeSession(configuration: sessionConfiguration)
    }

    deinit {
        session.invalidateAndCancel()
        pendingSMSLogin?.session.invalidateAndCancel()
        pendingManualLogin?.cancel()
    }

    public func ensureSession() async throws -> WUSTLoginResult {
        try await run(kind: .check) { try await self.checkSession() }
    }

    /// Creates a user-operated CAPTCHA session. The login form stays native; its view loads only the official CAPTCHA.
    public func prepareManualAuthServerLogin() throws -> ManualSliderCaptchaSession {
        guard !loggingOut, operation == nil else { throw WUSTLoginClientError.operationInProgress }
        try Task.checkCancellation()
        clearPendingSMSLogin()
        clearPendingManualLogin()
        let value = ManualSliderCaptchaSession(using: Self.makeSession(configuration: configuration))
        pendingManualLogin = value
        return value
    }

    public func cancelManualAuthServerLogin() { clearPendingManualLogin() }

    /// Continues the same session after ManualSliderCaptchaView reports server-confirmed success.
    public func loginWithManualAuthServer(password: String, verification: ManualSliderCaptchaSession) async throws -> WUSTLoginResult {
        try await withTaskCancellationHandler {
            try await run(kind: .login, cancelOnCallerCancellation: true) {
                try await self.performManualAuthServerLogin(password: password, verification: verification)
            }
        } onCancel: { verification.cancel() }
    }

    private func performManualAuthServerLogin(password: String, verification: ManualSliderCaptchaSession) async throws -> WUSTLoginResult {
        guard !password.isEmpty else { throw AuthServerLoginError.invalidInput }
        guard pendingManualLogin?.id == verification.id else { throw WUSTLoginClientError.verificationNotPending }
        let expectedVersion = version
        // Keep the reference until completion so logout/switching modes can invalidate it immediately.
        defer {
            if pendingManualLogin?.id == verification.id { pendingManualLogin = nil }
            verification.cancel()
        }
        let cookies = try await verification.complete(username: username, password: password)
        try checkActive(expectedVersion)
        return try await validateUndergraduateWebSession(cookies)
    }

    public func loginWithAuthServer(password: String, maxSliderAttempts: Int = 3,
                                    diagnostics: (@Sendable (SliderCaptchaDiagnostic) -> Void)? = nil) async throws -> WUSTLoginResult {
        try await run(kind: .login) {
            try await self.performAuthServerLogin(password: password, maxSliderAttempts: maxSliderAttempts, diagnostics: diagnostics)
        }
    }

    private func performAuthServerLogin(password: String, maxSliderAttempts: Int,
                                        diagnostics: (@Sendable (SliderCaptchaDiagnostic) -> Void)?) async throws -> WUSTLoginResult {
        clearPendingManualLogin()
        clearPendingSMSLogin()
        let expectedVersion = version
        let candidate = Self.makeSession(configuration: configuration)
        defer { candidate.invalidateAndCancel() }
        try await AuthServerLoginService().login(username: username, password: password, using: candidate,
                                                maxSliderAttempts: maxSliderAttempts, diagnostics: diagnostics)
        try checkActive(expectedVersion)
        let cookies = candidate.configuration.httpCookieStorage?.cookies ?? []
        return try await validateUndergraduateWebSession(cookies)
    }

    public func sendLoginSMSCode(
        to account: String, maxSliderAttempts: Int = 3,
        diagnostics: (@Sendable (SliderCaptchaDiagnostic) -> Void)? = nil
    ) async throws -> Int? {
        _ = try await run(kind: .login) {
            try await self.performSendLoginSMS(account: account, maxSliderAttempts: maxSliderAttempts, diagnostics: diagnostics)
        }
        return pendingSMSLogin?.context.resendAfterSeconds
    }

    public func loginWithSMSCode(_ code: String) async throws -> WUSTLoginResult {
        try await run(kind: .login) {
            try await self.performSMSLogin(code: code)
        }
    }

    private func performSendLoginSMS(
        account: String, maxSliderAttempts: Int,
        diagnostics: (@Sendable (SliderCaptchaDiagnostic) -> Void)?
    ) async throws -> WUSTLoginResult {
        clearPendingManualLogin()
        clearPendingSMSLogin()
        let expectedVersion = version
        let candidate = Self.makeSession(configuration: configuration)
        var prepared = false
        defer { if !prepared { candidate.invalidateAndCancel() } }
        let context = try await AuthServerSMSLoginService().sendCode(
            account: account, using: candidate, maxSliderAttempts: maxSliderAttempts, diagnostics: diagnostics
        )
        try checkActive(expectedVersion)
        pendingSMSLogin = (context, candidate)
        prepared = true
        return .loginRequired
    }

    private func performSMSLogin(code: String) async throws -> WUSTLoginResult {
        guard let pendingSMSLogin else { throw WUSTLoginClientError.verificationNotPending }
        let expectedVersion = version
        let result = try await AuthServerSMSLoginService().login(code: code, context: pendingSMSLogin.context, using: pendingSMSLogin.session)
        try checkActive(expectedVersion)
        if case .loginNotCompleted(let refreshed) = result {
            self.pendingSMSLogin = (refreshed, pendingSMSLogin.session)
            throw AuthServerLoginError.loginNotCompleted
        }
        let cookies = pendingSMSLogin.session.configuration.httpCookieStorage?.cookies ?? []
        return try await validateUndergraduateWebSession(cookies)
    }

    private func clearPendingManualLogin() {
        pendingManualLogin?.cancel()
        pendingManualLogin = nil
    }

    private func clearPendingSMSLogin() {
        pendingSMSLogin?.session.invalidateAndCancel()
        pendingSMSLogin = nil
    }

    func adoptUndergraduateWebSession(_ cookies: [HTTPCookie]) async throws -> WUSTLoginResult {
        try await run(kind: .login) { try await self.validateUndergraduateWebSession(cookies) }
    }

    private func validateUndergraduateWebSession(_ cookies: [HTTPCookie]) async throws -> WUSTLoginResult {
        let expectedVersion = version
        let url = URL(string: "https://bkjx.wust.edu.cn/jsxsd/grxx/xsxx")!
        let candidate = Self.makeSession(configuration: configuration)
        var accepted = false
        defer { if !accepted { candidate.invalidateAndCancel() } }

        let undergraduateCookies = cookies.filter {
            let domain = $0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain
            return domain.lowercased() == url.host
        }
        guard !undergraduateCookies.isEmpty, let storage = candidate.configuration.httpCookieStorage else {
            throw UndergraduateAuthServiceError.cookieMissing
        }
        storage.setCookies(undergraduateCookies, for: url, mainDocumentURL: url)

        let cookie = try await UndergraduateAuthService().currentSessionCookie(using: candidate)
        try checkActive(expectedVersion)
        _ = try await StudentInfoService().fetchStudentInfo(cookie: cookie, using: candidate)
        try checkActive(expectedVersion)

        version += 1
        clearPendingManualLogin()
        clearPendingSMSLogin()
        session.invalidateAndCancel()
        session = candidate
        accepted = true
        sessionInvalidated = false
        return .authenticated(cookie: cookie)
    }


    public func fetchStudentInfo() async throws -> StudentInfo {
        let expectedVersion = version
        let info = try await withUndergraduateSession { cookie, session in
            try await StudentInfoService().fetchStudentInfo(cookie: cookie, using: session)
        }
        try checkActive(expectedVersion)
        return info
    }

    public func withUndergraduateSession<Value: Sendable>(
        authenticationFailure: @Sendable (any Error) -> Bool = { _ in false },
        perform request: @Sendable (String, URLSession) async throws -> Value
    ) async throws -> Value {
        let expectedVersion = version
        guard case .authenticated(let cookie) = try await ensureSession() else {
            throw WUSTLoginClientError.notAuthenticated
        }
        try checkActive(expectedVersion)
        do {
            let value = try await request(cookie, session)
            try checkActive(expectedVersion)
            return value
        } catch {
            try checkActive(expectedVersion)
            if authenticationFailure(error) {
                sessionInvalidated = true
                throw WUSTLoginClientError.notAuthenticated
            }
            throw error
        }
    }

    func withAuthenticatedSession<Value: Sendable>(
        perform request: @Sendable (URLSession) async throws -> Value
    ) async throws -> Value {
        let expectedVersion = version
        guard case .authenticated = try await ensureSession() else {
            throw WUSTLoginClientError.notAuthenticated
        }
        try checkActive(expectedVersion)
        let value = try await request(session)
        try checkActive(expectedVersion)
        return value
    }

    public func logout() async throws {
        guard !loggingOut else { throw WUSTLoginClientError.operationInProgress }
        loggingOut = true
        defer { loggingOut = false }
        version += 1
        clearPendingManualLogin()
        clearPendingSMSLogin()
        let task = operation?.task
        operation = nil
        task?.cancel()
        session.invalidateAndCancel()
        session = Self.makeSession(configuration: configuration)
        sessionInvalidated = false
        if let task { _ = await task.result }
    }

    private func run(
        kind: OperationKind,
        cancelOnCallerCancellation: Bool = false,
        body: @escaping @Sendable () async throws -> WUSTLoginResult
    ) async throws -> WUSTLoginResult {
        guard !loggingOut else { throw WUSTLoginClientError.operationInProgress }
        if let active = operation {
            guard kind == .check && active.kind == .check else {
                throw WUSTLoginClientError.operationInProgress
            }
            return try await active.task.value
        }
        let id = UUID()
        let task = Task { try await body() }
        operation = (id, kind, task)
        defer { if operation?.id == id { operation = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            if cancelOnCallerCancellation { task.cancel() }
        }
    }

    private func checkSession() async throws -> WUSTLoginResult {
        let expectedVersion = version
        guard !sessionInvalidated else { return .loginRequired }
        do {
            let cookie = try await UndergraduateAuthService().currentSessionCookie(using: session)
            try checkActive(expectedVersion)
            return .authenticated(cookie: cookie)
        } catch UndergraduateAuthServiceError.cookieMissing {
            try checkActive(expectedVersion)
            return .loginRequired
        } catch UndergraduateAuthServiceError.invalidSession {
            try checkActive(expectedVersion)
            sessionInvalidated = true
            return .loginRequired
        }
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
}
