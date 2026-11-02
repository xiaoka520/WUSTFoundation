import Foundation
import Testing
@testable import WUSTFoundation

@Suite(.serialized)
struct WUSTLoginClientTests {
    init() { LoginTestServer.shared.reset() }

    @Test func missingCredentialRequiresLoginWithoutNetwork() async throws {
        let client = try testClient(credential: nil)
        guard case .loginRequired = try await client.ensureSession() else { Issue.record("Expected loginRequired"); return }
        #expect(LoginTestServer.shared.requests().isEmpty)
    }

    @Test func restoreThenReuseWithoutMintingAnotherST() async throws {
        let client = try testClient()
        #expect(isAuthenticated(try await client.ensureSession()))
        let count = LoginTestServer.shared.count("/lyuapServer/v1/tickets/TGT-test")
        #expect(count == 2)
        #expect(isAuthenticated(try await client.ensureSession()))
        #expect(LoginTestServer.shared.count("/lyuapServer/v1/tickets/TGT-test") == count)
        #expect(LoginTestServer.shared.count("/lyuapServer/v1/tickets") == 0)
        #expect(LoginTestServer.shared.count("/lyuapServer/kaptcha") == 0)
        let requests = LoginTestServer.shared.requests()
        let configs = requests.filter { $0.url?.path == "/passport/v1/public/authConfig" }
        #expect(configs.allSatisfy { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "mod", value: "1")) == true })
        let report = try #require(requests.first { $0.url?.path == "/controller/v1/public/reportEnv" })
        #expect(report.value(forHTTPHeaderField: "x-csrf-token") == "test-csrf")
        let request = try ATrustAuthRequestFactory().makeEnvironmentReportRequest(environmentTicket: "test-environment-ticket", deviceID: "test-device", csrfToken: "test-csrf")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["ticket"] as? String == "test-environment-ticket")
        #expect(json["deviceId"] as? String == "test-device")
    }

    @Test func expiredTGTIsCleared() async throws {
        let store = TestCredentialStore()
        await store.saveCredential(UnionCredential(tgt: "TGT-test"), for: "test-account")
        LoginTestServer.shared.update { $0.expired = true }
        let client = try testClient(store: store, credential: nil)
        guard case .loginRequired = try await client.ensureSession() else { Issue.record("Expected expired credential"); return }
        #expect(await client.currentCredential() == nil)
        #expect(await store.loadCredential(for: "test-account") == nil)
    }

    @Test func offlineDoesNotEraseTGT() async throws {
        let store = TestCredentialStore()
        await store.saveCredential(UnionCredential(tgt: "TGT-test"), for: "test-account")
        LoginTestServer.shared.update { $0.offline = true }
        let client = try testClient(store: store, credential: nil)
        await #expect(throws: URLError.self) { try await client.ensureSession() }
        #expect(await store.loadCredential(for: "test-account")?.tgt == "TGT-test")
    }

    @Test func concurrentRestoreIsShared() async throws {
        LoginTestServer.shared.update { $0.delay = 0.01 }
        let client = try testClient()
        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<12 { group.addTask { isAuthenticated(try await client.ensureSession()) } }
            var results: [Bool] = []
            for try await result in group { results.append(result) }
            return results
        }
        #expect(results.count == 12 && results.allSatisfy { $0 })
        #expect(LoginTestServer.shared.count("/lyuapServer/v1/tickets/TGT-test") == 2)
    }

    @Test func logoutCancelsRestoreAndLeavesNoCredential() async throws {
        LoginTestServer.shared.update { $0.delay = 0.05 }
        let store = TestCredentialStore()
        await store.saveCredential(UnionCredential(tgt: "TGT-test"), for: "test-account")
        let client = try testClient(store: store, credential: nil)
        let task = Task { try await client.ensureSession() }
        try await waitUntil { LoginTestServer.shared.count("/passport/v1/public/authConfig") > 0 }
        try await client.logout()
        if case .success = await task.result { Issue.record("Logged-out operation returned success") }
        #expect(await client.currentCredential() == nil)
        #expect(await store.loadCredential(for: "test-account") == nil)
        guard case .loginRequired = try await client.ensureSession() else { Issue.record("Old task revived session"); return }
    }

    @Test func freshClientLoadsAccountScopedStore() async throws {
        let store = TestCredentialStore()
        let first = try testClient(store: store, credential: nil)
        #expect(isAuthenticated(try await first.login(password: "synthetic-password")))
        let second = try testClient(store: store, credential: nil)
        #expect(isAuthenticated(try await second.ensureSession()))
        #expect(LoginTestServer.shared.count("/lyuapServer/v1/tickets") == 1)
        #expect(await store.loadCredential(for: "another-account") == nil)
        try await first.logout()
        #expect(await store.loadCredential(for: "test-account") == nil)
    }

    @Test func smsContinuationIsExplicitAndConsumesChallenge() async throws {
        LoginTestServer.shared.update { $0.needSMS = true }
        let client = try testClient(credential: nil)
        guard case .verificationRequired(_, let methods) = try await client.login(password: "synthetic-password") else { Issue.record("Missing challenge"); return }
        #expect(methods == [.sms])
        #expect(LoginTestServer.shared.count("/lyuapServer/login/mobile/generateCode") == 0)
        try await client.sendSMSCode()
        #expect(isAuthenticated(try await client.submitSMSCode("synthetic-code", password: "synthetic-password")))
        #expect(LoginTestServer.shared.count("/lyuapServer/kaptcha") == 2)
        #expect(LoginTestServer.shared.count("/lyuapServer/login/mobile/generateCode") == 1)
        await #expect(throws: WUSTLoginClientError.self) { try await client.submitSMSCode("again", password: "synthetic-password") }
    }

    @Test func unknownATrustStepIsNotAuthenticated() async throws {
        LoginTestServer.shared.update { $0.nextService = "auth/extra" }
        let client = try testClient()
        guard case .additionalAuthenticationRequired(let next) = try await client.ensureSession() else { Issue.record("Unknown step accepted"); return }
        #expect(next == "auth/extra")
        #expect(LoginTestServer.shared.count("/jsxsd/") == 0)
    }

    @Test func environmentRejectionDoesNotReachAuthCheck() async throws {
        LoginTestServer.shared.update { $0.reportFailure = true }
        let client = try testClient()
        await #expect(throws: ATrustAuthServiceError.self) { try await client.ensureSession() }
        #expect(LoginTestServer.shared.count("/passport/v1/auth/authCheck") == 0)
    }

    @Test func unknownSessionBodyIsNotSuccessOrAutomaticRelogin() async throws {
        let client = try testClient()
        #expect(isAuthenticated(try await client.ensureSession()))
        LoginTestServer.shared.update { $0.blankPageBody = "unknown response" }
        let tickets = LoginTestServer.shared.count("/lyuapServer/v1/tickets/TGT-test")
        await #expect(throws: UndergraduateAuthServiceError.self) { try await client.ensureSession() }
        #expect(LoginTestServer.shared.count("/lyuapServer/v1/tickets/TGT-test") == tickets)
    }

    @Test func captchaRecognitionRetriesOnlyImages() async throws {
        let client = try testClient(credential: nil, solver: { _ in throw CaptchaRecognitionError.noText })
        await #expect(throws: WUSTLoginClientError.self) { try await client.login(password: "synthetic-password") }
        #expect(LoginTestServer.shared.count("/lyuapServer/kaptcha") == 3)
        #expect(LoginTestServer.shared.count("/lyuapServer/v1/tickets") == 0)
    }
    @Test func logoutWaitsForInFlightSaveBeforeClearing() async throws {
        let store = TestCredentialStore()
        await store.pauseNextSave()
        let client = try testClient(store: store, credential: nil)
        let login = Task { try await client.login(password: "synthetic-password") }
        try await waitUntil { await store.saving }
        let logout = Task { try await client.logout() }
        try await waitUntil { await client.currentCredential() == nil }
        await store.resumeSave()
        try await logout.value
        if case .success = await login.result { Issue.record("Cancelled login succeeded") }
        #expect(await store.loadCredential(for: "test-account") == nil)
        #expect(await client.currentCredential() == nil)
    }

    @Test func expiredDuringUndergraduateMintAlsoClearsCredential() async throws {
        LoginTestServer.shared.update { $0.expireOnMint = 2 }
        let store = TestCredentialStore()
        await store.saveCredential(UnionCredential(tgt: "TGT-test"), for: "test-account")
        let client = try testClient(store: store, credential: nil)
        guard case .loginRequired = try await client.ensureSession() else { Issue.record("Expected expiration"); return }
        #expect(await store.loadCredential(for: "test-account") == nil)
    }

    @Test func redirectedCookieCheckTriggersOneRecovery() async throws {
        let client = try testClient()
        #expect(isAuthenticated(try await client.ensureSession()))
        LoginTestServer.shared.update { $0.blankPageRedirect = true }
        #expect(isAuthenticated(try await client.ensureSession()))
        #expect(LoginTestServer.shared.count("/lyuapServer/v1/tickets/TGT-test") == 4)
    }

    @Test func studentInformationUsesSessionAndRejectsAnotherAccount() async throws {
        let store = TestCredentialStore()
        let client = try testClient(store: store, credential: nil)
        #expect(isAuthenticated(try await client.login(password: "synthetic-password")))
        #expect(try await client.fetchStudentInfo().studentID == "test-account")
        LoginTestServer.shared.update { $0.studentID = "another-synthetic-account" }
        await #expect(throws: WUSTLoginClientError.self) { try await client.fetchStudentInfo() }
        #expect(await client.currentCredential() == nil)
        #expect(await store.loadCredential(for: "test-account") == nil)
    }

    @Test func smsRejectionDoesNotAutomaticallyResendOrLoseChallenge() async throws {
        LoginTestServer.shared.update { $0.needSMS = true; $0.smsFailure = true }
        let client = try testClient(credential: nil)
        _ = try await client.login(password: "synthetic-password")
        await #expect(throws: UnionAuthServiceError.self) { try await client.sendSMSCode() }
        #expect(LoginTestServer.shared.count("/lyuapServer/login/mobile/generateCode") == 1)
        LoginTestServer.shared.update { $0.smsFailure = false }
        try await client.sendSMSCode()
        #expect(LoginTestServer.shared.count("/lyuapServer/login/mobile/generateCode") == 2)
    }

    @Test func concurrentLoginDoesNotJoinUnrelatedRestore() async throws {
        LoginTestServer.shared.update { $0.delay = 0.01 }
        let client = try testClient()
        let restore = Task { try await client.ensureSession() }
        try await waitUntil { LoginTestServer.shared.count("/passport/v1/public/authConfig") > 0 }
        await #expect(throws: WUSTLoginClientError.self) { try await client.login(password: "synthetic-password") }
        #expect(isAuthenticated(try await restore.value))
        #expect(LoginTestServer.shared.count("/lyuapServer/v1/tickets") == 0)
    }

    private func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw URLError(.timedOut)
    }

}
