// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The sheet behind "What Changed…": rows from jit's JSON, never a pane of
/// its text. jit's words appear only under a failure.
final class ChangeSheetTests: XCTestCase {
    private func cache(
        _ agent: String, _ area: String, path: String = "/h/x", copies: Int? = nil, kind: String? = nil, reason: String? = nil
    ) -> MigrateReport.CacheFile {
        .init(agent: agent, area: area, path: path, copies: copies, kind: kind, reason: reason)
    }

    func testARedactNamesEveryFileItsAgentAndItsTokens() {
        let sheet = ChangeSheet.redact(RedactReport(
            files: [], applied: true,
            caches: .init(removed: [
                cache("Claude Code", "prompt history", path: "/h/.claude/history.jsonl", copies: 1),
                cache("Claude Code", "transcripts", path: "/h/.claude/projects/p/a.jsonl", copies: 122)
            ]),
            errors: [], report: "AI agent caches\n  123 tokens …"
        ))
        XCTAssertEqual(sheet.title, "Redacted 123 tokens in 2 files")
        XCTAssertEqual(sheet.sentence, "All in Claude Code's prompt history and transcripts. Your own files were not touched.")
        XCTAssertEqual(sheet.files.map(\.path), ["/h/.claude/history.jsonl", "/h/.claude/projects/p/a.jsonl"])
        XCTAssertEqual(sheet.files.map(\.fact), ["Claude Code · prompt history · 1 token", "Claude Code · transcripts · 122 tokens"])
        XCTAssertEqual(sheet.notes.map(\.mark), [.done, .done])
        XCTAssertNil(sheet.notes.first { $0.verbatim != nil }, "a success carries none of jit's words on screen")
        XCTAssertEqual(sheet.report, "AI agent caches\n  123 tokens …", "jit's report is kept for the disclosure")
        XCTAssertFalse(sheet.failed)
        XCTAssertEqual(sheet.undo, [])
    }

    func testAFailureLeadsWithJitsWordsAndWhatStillChanged() {
        let sheet = ChangeSheet.redact(RedactReport(
            files: [], applied: true,
            caches: .init(
                removed: [cache("Claude Code", "transcripts", copies: 2)],
                left: [cache("Claude Code", "transcripts", kind: "live")]
            ),
            errors: ["open /h/b.jsonl: permission denied"], report: ""
        ))
        XCTAssertTrue(sheet.failed)
        XCTAssertEqual(sheet.notes.first?.mark, .failed)
        XCTAssertEqual(sheet.notes.first?.fact, "What changed below stays changed.")
        XCTAssertEqual(sheet.notes.first?.verbatim, "open /h/b.jsonl: permission denied")
        XCTAssertEqual(sheet.notes.last, .init(
            mark: .left, name: "1 file left in Claude Code's transcripts",
            fact: "Claude Code is writing it. The next scan tries again."
        ))
    }

    func testNothingToRedact() {
        let sheet = ChangeSheet.redact(RedactReport(files: [], applied: false, caches: .init(), errors: [], report: ""))
        XCTAssertEqual(sheet.title, "Nothing to redact")
        XCTAssertEqual(sheet.notes, [])
    }

    func testAProtectListsItsFilesTheVaultedNamesAndTheCopies() {
        let report = MigrateReport(
            targets: ["/h/notion/.env", "/h/okta/.env"], applied: true, vaulted: ["NOTION_TOKEN", "OKTA_API_TOKEN"],
            caches: .init(
                removed: [cache("Claude Code", "transcripts", copies: 6), cache("Cursor", "history", copies: 2)],
                left: [cache("Claude Code", "transcripts", kind: "live")]
            ),
            errors: [], report: "text"
        )
        let sheet = ChangeSheet.protect([report], wrapped: ["gh"], report: "text")
        XCTAssertEqual(sheet.title, "Protected 2 files · 2 secrets are in the vault")
        XCTAssertEqual(sheet.files.map(\.path), ["/h/notion/.env", "/h/okta/.env"])
        XCTAssertEqual(sheet.undo, ["/h/notion/.env", "/h/okta/.env"])
        XCTAssertEqual(sheet.notes.map(\.name), [
            "In the vault", "8 cached copies removed", "Wrapped gh", "1 file left in Claude Code's transcripts"
        ])
        XCTAssertEqual(sheet.notes[0].fact, "NOTION_TOKEN, OKTA_API_TOKEN")
        XCTAssertEqual(sheet.notes[1].fact, "Claude Code's transcripts, Cursor's history")
    }

    func testAProtectThatChangedNothingOffersNoUndo() {
        let report = MigrateReport(
            targets: ["/h/a/.env"],
            applied: false,
            vaulted: [],
            caches: .init(),
            errors: ["vault locked"],
            report: ""
        )
        let sheet = ChangeSheet.protect([report], report: "")
        XCTAssertEqual(sheet.title, "Protect did not finish")
        XCTAssertEqual(sheet.undo, [])
        XCTAssertEqual(sheet.notes.first?.fact, "Nothing was changed.")
    }
}
