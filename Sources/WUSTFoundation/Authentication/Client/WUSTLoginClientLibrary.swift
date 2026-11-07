import Foundation

extension WUSTLoginClient {
    public func fetchLibraryDashboard(pageSize: Int = 100) async throws -> LibraryDashboard {
        try await withUnionCredentialAndSession { credential, session in
            try await LibraryService(pageSize: pageSize).fetchDashboard(
                credential: credential,
                using: session
            )
        }
    }

    public func fetchLibraryStatistics() async throws -> LibraryStatistics {
        try await withLibraryQuery { service, cookie, session in
            try await service.fetchStatistics(cookie: cookie, using: session)
        }
    }

    public func fetchLibraryCurrentLoans(page: Int = 1, pageSize: Int = 10) async throws -> LibraryPage<LibraryLoan> {
        try await withLibraryQuery { service, cookie, session in
            try await service.fetchCurrentLoans(cookie: cookie, page: page, pageSize: pageSize, using: session)
        }
    }

    public func fetchLibraryOverdueSoon(page: Int = 1, pageSize: Int = 10) async throws -> LibraryPage<LibraryLoan> {
        try await withLibraryQuery { service, cookie, session in
            try await service.fetchOverdueSoon(cookie: cookie, page: page, pageSize: pageSize, using: session)
        }
    }

    public func fetchLibraryRequests(page: Int = 1, pageSize: Int = 5) async throws -> LibraryPage<LibraryRecord> {
        try await withLibraryQuery { service, cookie, session in
            try await service.fetchRequests(cookie: cookie, page: page, pageSize: pageSize, using: session)
        }
    }

    public func fetchLibraryFines(page: Int = 1, pageSize: Int = 10) async throws -> LibraryPage<LibraryRecord> {
        try await withLibraryQuery { service, cookie, session in
            try await service.fetchFines(cookie: cookie, page: page, pageSize: pageSize, using: session)
        }
    }

    public func fetchLibraryBooklists() async throws -> [LibraryBooklist] {
        try await withLibraryQuery { service, cookie, session in
            try await service.fetchBooklists(cookie: cookie, using: session)
        }
    }

    public func fetchLibraryBooklistInfo(id: String) async throws -> LibraryBooklist {
        try await withLibraryQuery { service, cookie, session in
            try await service.fetchBooklistInfo(id: id, cookie: cookie, using: session)
        }
    }

    public func fetchLibraryBooklistBooks(
        id: String, page: Int = 1, pageSize: Int = 10
    ) async throws -> LibraryPage<LibraryRecord> {
        try await withLibraryQuery { service, cookie, session in
            try await service.fetchBooklistBooks(id: id, cookie: cookie, page: page, pageSize: pageSize, using: session)
        }
    }

    private func withLibraryQuery<Value: Sendable>(
        _ query: @Sendable (LibraryService, String, URLSession) async throws -> Value
    ) async throws -> Value {
        try await withUnionCredentialAndSession { credential, session in
            let service = LibraryService()
            return try await service.withLibraryCookie(credential: credential, using: session) { cookie in
                try await query(service, cookie, session)
            }
        }
    }
}
