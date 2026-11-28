import Foundation
import Testing
@testable import WUSTFoundation

@Suite(.serialized)
struct WUSTLoginClientTests {
    init() { LoginTestServer.shared.reset() }

    @Test func avatarUsesRetainedAuthCookiesAndExplicitStudentInfoOption() async throws {
        let image = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="
        LoginTestServer.shared.update {
            $0.avatarJSON = #"{"code":"0","datas":{"headImageIcon":""# + image + #""}}"#
        }
        let token = try #require(HTTPCookie(properties: [
            .domain: "auth.wust.edu.cn", .path: "/", .name: "REFERERCE_TOKEN",
            .value: "synthetic-token", .secure: "TRUE"
        ]))
        let client = try testClient()
        _ = try await client.adoptUndergraduateWebSession([testUndergraduateCookie(), token])
        #expect(try await client.fetchStudentInfo().avatarData == nil)
        #expect(LoginTestServer.shared.count("/personalInfo/personCenter/index.html") == 0)
        let info = try await client.fetchStudentInfo(includeAvatar: true)
        #expect(info.avatarData == Data(base64Encoded: image))
        let request = try #require(LoginTestServer.shared.requests().last { $0.url?.path.hasSuffix("/queryUserData") == true })
        #expect(request.value(forHTTPHeaderField: "refererToken") == "synthetic-token")
        #expect(request.url?.host == "auth.wust.edu.cn")
        try await client.logout()
        await #expect(throws: WUSTLoginClientError.notAuthenticated) { try await client.fetchStudentAvatar() }
    }

    @Test func avatarAbsenceAndExpiredAuthSessionAreDistinct() async throws {
        let client = try testClient()
        _ = try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])
        #expect(try await client.fetchStudentAvatar() == nil)
        LoginTestServer.shared.update { $0.avatarLoginRequired = true }
        await #expect(throws: StudentAvatarError.authenticationRequired) { try await client.fetchStudentAvatar() }
        #expect(isAuthenticated(try await client.ensureSession()))
    }

    @Test func avatarRejectsMalformedImageAndBusinessFailure() throws {
        #expect(throws: StudentAvatarError.invalidImage) {
            try StudentAvatarService.avatar(from: Data(#"{"code":"0","datas":{"headImageIcon":"aGVsbG8="}}"#.utf8))
        }
        #expect(throws: StudentAvatarError.authenticationRequired) {
            try StudentAvatarService.avatar(from: Data(#"{"code":"2106040302"}"#.utf8))
        }
        #expect(throws: StudentAvatarError.rejected("failure")) {
            try StudentAvatarService.avatar(from: Data(#"{"code":"failure"}"#.utf8))
        }
    }

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

    @Test func phoneUsernameAcceptsAuthenticatedStudentSession() async throws {
        let client = try testClient(username: "13800000000")
        #expect(isAuthenticated(try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])))
        #expect(try await client.fetchStudentInfo().studentID == "test-account")
        #expect(isAuthenticated(try await client.ensureSession()))
        // A valid adopted session is reused without another auth request or SMS send.
        #expect(LoginTestServer.shared.requests().allSatisfy { $0.url?.host == "bkjx.wust.edu.cn" && $0.httpMethod == "GET" })
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

    @Test func studentInfoReadReturnsServerIdentityAndKeepsSession() async throws {
        let client = try testClient()
        _ = try await client.adoptUndergraduateWebSession([testUndergraduateCookie()])
        LoginTestServer.shared.update { $0.studentID = "another-account" }
        #expect(try await client.fetchStudentInfo().studentID == "another-account")
        #expect(isAuthenticated(try await client.ensureSession()))
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
