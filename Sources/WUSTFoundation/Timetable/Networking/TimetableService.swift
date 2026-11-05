//
//  File.swift
//  WUSTFoundation
//
//  Created by 曹恩铭 on 2026/11/2.
//

import Foundation

public struct TimetableService: Sendable {
    private let maxWeek: Int
    private let maxSection: Int

    public init(maxWeek: Int = 30, maxSection: Int = 12) {
        self.maxWeek = maxWeek
        self.maxSection = maxSection
    }

    public func fetchAcademicTerms(
        cookie: String,
        using session: URLSession
    ) async throws -> AcademicTermList {
        let entry = try await fetchEntry(cookie: cookie, using: session)
        return entry.terms
    }

    public func fetchTimetable(
        term: AcademicTerm,
        cookie: String,
        using session: URLSession
    ) async throws -> Timetable {
        guard maxWeek > 0, maxSection > 0 else {
            throw TimetableError.invalidNumberList
        }

        let entry = try await fetchEntry(cookie: cookie, using: session)
        guard let requestedTerm = entry.terms.terms.first(where: { $0.id == term.id }) else {
            throw TimetableError.invalidTerm
        }
        let templateID = try singleValue(named: "kbjcmsid", in: entry.form)
        guard !templateID.isEmpty else {
            throw TimetableError.unsupportedForm
        }

        let request = try TimetableRequestFactory().makeTimetableRequest(
            url: entry.form.actionURL,
            fields: entry.form.fields,
            termID: requestedTerm.id,
            cookie: currentCookie(
                for: entry.form.actionURL,
                fallback: cookie,
                using: session
            )
        )
        let page = try await TimetablePageLoader().fetch(request, using: session)
        let returnedForm = try TimetableFormParser().parse(
            from: page.html,
            sourceURL: page.url
        )
        guard try singleValue(named: "xnxq01id", in: returnedForm) == requestedTerm.id,
              try singleValue(named: "zc", in: returnedForm).isEmpty,
              try singleValue(named: "kbjcmsid", in: returnedForm) == templateID else {
            throw TimetableError.selectionNotReflected
        }

        let returnedTerms = try TimetableParser().parseAcademicTerms(from: page.html)
        guard let returnedTerm = returnedTerms.terms.first(where: { $0.id == requestedTerm.id }) else {
            throw TimetableError.selectionNotReflected
        }
        return try TimetableParser().parse(
            from: page.html,
            term: returnedTerm,
            maxWeek: maxWeek,
            maxSection: maxSection
        )
    }

    private func fetchEntry(
        cookie: String,
        using session: URLSession
    ) async throws -> (form: TimetableForm, terms: AcademicTermList) {
        guard !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TimetableError.authenticationRequired
        }
        let request = try TimetableRequestFactory().makeEntryRequest(cookie: cookie)
        let page = try await TimetablePageLoader().fetch(request, using: session)
        let form = try TimetableFormParser().parse(
            from: page.html,
            sourceURL: page.url
        )
        let terms = try TimetableParser().parseAcademicTerms(from: page.html)
        return (form: form, terms: terms)
    }

    private func singleValue(
        named name: String,
        in form: TimetableForm
    ) throws -> String {
        let items = form.fields.filter { $0.name == name }
        guard items.count == 1, let value = items.first?.value else {
            throw TimetableError.unsupportedForm
        }
        return value
    }

    private func currentCookie(
        for url: URL,
        fallback: String,
        using session: URLSession
    ) -> String {
        let cookies = session.configuration.httpCookieStorage?.cookies(for: url) ?? []
        guard !cookies.isEmpty,
              let cookie = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"],
              !cookie.isEmpty else {
            return fallback
        }
        return cookie
    }
}
