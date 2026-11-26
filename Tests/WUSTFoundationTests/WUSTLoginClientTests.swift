import Foundation
import Testing
@testable import WUSTFoundation

@Suite(.serialized)
struct WUSTLoginClientTests {
    init() { LoginTestServer.shared.reset() }

    @Test func missingSessionRequiresLoginWithoutNetwork() async throws {
        let client = try testClient()
        guard case .loginRequired = try await client.ensureSession() else { Issue.record("Expected loginRequired"); return }
        #expect(LoginTestServer.shared.requests().isEmpty)
    }

    @Test func adoptedSessionIsVerifiedAndReused() async throws {
        let client = try testClient()
        #expect(isAuthenticated(try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])))
        #expect(isAuthenticated(try await client.ensureSession()))
        #expect(try await client.fetchStudentInfo().studentID == "test-account")
        #expect(LoginTestServer.shared.requests().allSatisfy { $0.url?.host == "bkjx.wust.edu.cn" })
    }

    @Test func anotherAccountIsNotAdopted() async throws {
        LoginTestServer.shared.update { $0.studentID = "other-account" }
        let client = try testClient()
        await #expect(throws: WUSTLoginClientError.studentIDMismatch) {
            try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])
        }
        guard case .loginRequired = try await client.ensureSession() else { Issue.record("Wrong account adopted"); return }
    }

    @Test func offlineDoesNotDiscardAnExistingSession() async throws {
        let client = try testClient()
        _ = try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])
        LoginTestServer.shared.update { $0.offline = true }
        await #expect(throws: URLError.self) { try await client.ensureSession() }
        LoginTestServer.shared.update { $0.offline = false }
        #expect(isAuthenticated(try await client.ensureSession()))
    }

    @Test func expiredSessionRequiresLoginWithoutLegacyFallback() async throws {
        let client = try testClient()
        _ = try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])
        LoginTestServer.shared.update { $0.blankPageRedirect = true }
        guard case .loginRequired = try await client.ensureSession() else { Issue.record("Expired session reused"); return }
        #expect(LoginTestServer.shared.requests().allSatisfy { $0.url?.host == "bkjx.wust.edu.cn" })
    }

    @Test func unknownCheckPageIsAnErrorRatherThanLoginRequired() async throws {
        let client = try testClient()
        _ = try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])
        LoginTestServer.shared.update { $0.blankPageBody = "unexpected response" }
        await #expect(throws: UndergraduateAuthServiceError.invalidResponse) { try await client.ensureSession() }
        LoginTestServer.shared.update { $0.blankPageBody = "" }
        #expect(isAuthenticated(try await client.ensureSession()))
    }

    @Test func concurrentChecksShareOneRequest() async throws {
        let client = try testClient()
        _ = try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])
        let before = LoginTestServer.shared.count("/jsxsd/framework/blankPage.jsp")
        LoginTestServer.shared.update { $0.delay = 0.05 }
        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<12 { group.addTask { isAuthenticated(try await client.ensureSession()) } }
            var results: [Bool] = []
            for try await result in group { results.append(result) }
            return results
        }
        #expect(results.count == 12 && results.allSatisfy { $0 })
        #expect(LoginTestServer.shared.count("/jsxsd/framework/blankPage.jsp") == before + 1)
    }

    @Test func logoutCancelsCheckAndCannotReviveSession() async throws {
        let client = try testClient()
        _ = try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])
        let before = LoginTestServer.shared.count("/jsxsd/framework/blankPage.jsp")
        LoginTestServer.shared.update { $0.delay = 0.05 }
        let task = Task { try await client.ensureSession() }
        try await waitUntil { LoginTestServer.shared.count("/jsxsd/framework/blankPage.jsp") > before }
        try await client.logout()
        if case .success = await task.result { Issue.record("Logged-out request returned success") }
        guard case .loginRequired = try await client.ensureSession() else { Issue.record("Old task revived session"); return }
    }

    @Test func accountMismatchDuringReadClearsSession() async throws {
        let client = try testClient()
        _ = try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])
        LoginTestServer.shared.update { $0.studentID = "another-account" }
        await #expect(throws: WUSTLoginClientError.studentIDMismatch) { try await client.fetchStudentInfo() }
        guard case .loginRequired = try await client.ensureSession() else { Issue.record("Wrong account session retained"); return }
    }

    @Test func authenticationFailureRequiresInteractionWithoutRetryingOldEndpoints() async throws {
        let client = try testClient()
        _ = try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])
        await #expect(throws: WUSTLoginClientError.notAuthenticated) {
            try await client.withUndergraduateSession(authenticationFailure: { $0 is TimetableError }) { _, _ -> String in
                throw TimetableError.authenticationRequired
            }
        }
        guard case .loginRequired = try await client.ensureSession() else { Issue.record("Known-invalid session reused"); return }
        #expect(LoginTestServer.shared.requests().allSatisfy { $0.url?.host == "bkjx.wust.edu.cn" })
    }

    @Test func libraryNeedsItsOwnSessionAndDoesNotMintOldTickets() async throws {
        let client = try testClient()
        _ = try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])
        await #expect(throws: LibraryError.authenticationRequired) { try await client.fetchLibraryDashboard() }
        #expect(LoginTestServer.shared.requests().allSatisfy { $0.url?.host == "bkjx.wust.edu.cn" })
    }

    @Test func aNewClientDoesNotInheritAnotherClientsSession() async throws {
        let first = try testClient()
        _ = try await first.adoptUndergraduateWebSession([testUndergraduateCookie()])
        let second = try testClient()
        guard case .loginRequired = try await second.ensureSession() else { Issue.record("Sessions were shared"); return }
        #expect(isAuthenticated(try await first.ensureSession()))
    }
}
