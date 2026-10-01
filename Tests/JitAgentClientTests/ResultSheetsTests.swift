// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The result sheets that replaced jit's printout: a result is a title, one
/// sentence and rows, built from jit 2.3.8's JSON. jit's words are on screen
/// only under a failure; the rest is behind the disclosure.
final class ResultSheetsTests: XCTestCase {
    // MARK: - Wrap

    func testAWrapFromItsFileSaysWhereTheKeyCameFromAndThatTheFileWasEmptied() throws {
        let report = try WrapReport.parse(Data(#"""
        {"tool":"hf","kind":"shim","wrapped":true,
         "key":{"var":"HF_TOKEN","vault_path":"wrap-hf/HF_TOKEN","from":"file","source":"~/.cache/huggingface/token","scrubbed":true},
         "shim":"~/.jit/shims/hf","profile":"wrap-hf","vaulted":[],"errors":[],"report":"Wrapped hf:"}
        """#.utf8))
        let sheet = ChangeSheet.wrapped(report, verify: true)
        XCTAssertEqual(sheet.title, "Wrapped hf")
        XCTAssertEqual(sheet.sentence, "hf's key is in the vault. jit hands it to hf each time it runs.")
        XCTAssertEqual(sheet.notes.map(\.name), ["HF_TOKEN moved to the vault", "hf now runs through jit"])
        XCTAssertEqual(sheet.notes[0].fact, "From ~/.cache/huggingface/token, now emptied · wrap-hf/HF_TOKEN")
        XCTAssertEqual(sheet.verify, "hf", "the sheet's Verify runs the catalog's check")
        XCTAssertNil(sheet.notes.first { $0.verbatim != nil }, "a success shows none of jit's words")
        XCTAssertEqual(sheet.report, "Wrapped hf:", "they stay behind the disclosure")
    }

    /// The app stored the typed key, then the wrap failed: the failure
    /// leads, with jit's line, and the stored key still stands as a row.
    func testAWrapThatFailedAfterTheKeyWasStoredSaysBoth() {
        let report = WrapReport(tool: "acme-cli", kind: "", wrapped: false, errors: ["acme-cli: not found on PATH"])
        let sheet = ChangeSheet.wrapped(report, stored: "wrap-acme-cli/ACME_API_TOKEN")
        XCTAssertEqual(sheet.title, "Stored acme-cli's key · the wrap failed")
        XCTAssertTrue(sheet.failed)
        XCTAssertEqual(sheet.notes.first?.name, "acme-cli was not wrapped")
        XCTAssertEqual(sheet.notes.first?.verbatim, "acme-cli: not found on PATH")
        XCTAssertEqual(sheet.notes.map(\.mark), [.failed, .done])
        XCTAssertEqual(sheet.notes[1].name, "ACME_API_TOKEN stored")
        XCTAssertNil(sheet.verify, "no Verify on a wrap that didn't happen")
    }

    func testAGrantWrapWhoseFileIsNotMigratedSaysSo() {
        let report = WrapReport(tool: "sops", kind: "grant", wrapped: true, grant: "sops", grantMigrated: false)
        let sheet = ChangeSheet.wrapped(report)
        XCTAssertEqual(sheet.notes.map(\.mark), [.done, .left])
        XCTAssertEqual(sheet.notes[1].name, "That file isn't in the vault yet")
    }

    /// Protect in Tools is `jit wrap <native tool> --yes --format json`:
    /// the sheet is the migration's own What Changed rows.
    func testANativeWrapIsItsMigrationsRows() {
        let migrate = MigrateReport(
            targets: ["/h/.aws/credentials"], applied: true, vaulted: ["aws_access_key_id", "aws_secret_access_key"],
            caches: .init(), errors: [], report: "Migrated."
        )
        let sheet = ChangeSheet.wrapped(WrapReport(tool: "aws", kind: "native", wrapped: true, migrate: migrate, report: "Migrated."))
        XCTAssertEqual(sheet.title, "Protected aws · 2 secrets are in the vault")
        XCTAssertEqual(sheet.files.map(\.path), ["/h/.aws/credentials"])
        XCTAssertEqual(sheet.undo, ["/h/.aws/credentials"])
    }

    // MARK: - Clean caches and undo

    func testCleanCachesListsEachFileAndWhatWasLeft() {
        let report = MigrateReport(
            targets: [], applied: true, vaulted: [],
            caches: .init(
                removed: [.init(agent: "Claude Code", area: "prompt history", path: "/h/.claude/history.jsonl", copies: 9)],
                left: [.init(agent: "Claude Code", area: "transcripts", path: "/h/.claude/p/s.jsonl", kind: "live")]
            ),
            errors: [], report: "Cleared 9 copies"
        )
        let sheet = ChangeSheet.caches(report)
        XCTAssertEqual(sheet.title, "Cleaned 9 copies in 1 file")
        XCTAssertEqual(sheet.files.map(\.fact), ["Claude Code · prompt history · 9 copies"])
        XCTAssertEqual(sheet.notes.map(\.mark), [.left])
        XCTAssertEqual(sheet.notes[0].fact, "Claude Code is writing it. The next scan tries again.")
        XCTAssertEqual(sheet.undo, ["/h/.claude/history.jsonl"])
    }

    func testAnUndoSaysWhichSecretsAreInPlainTextAndOffersProtectAgain() throws {
        let report = try UndoReport.parse(Data(#"""
        {"dry_run":false,"files":[
          {"path":"/h/billing/.env","action":"restore","backed_up_unix":1751000000,"mount":true,
           "secrets":["billing/DATABASE_URL","billing/STRIPE_KEY"],"restored":true},
          {"path":"/h/notes/.env","action":"restore","backed_up_unix":1751000000,"mount":false,"secrets":[],
           "restored":false,"error":"no backup recorded"}
        ],"errors":["jit migrate undo: 1 of 2 files failed to restore"],"report":"Restored 1 file."}
        """#.utf8))
        let sheet = ChangeSheet.restored(report)
        XCTAssertEqual(sheet.title, "Restored 1 file")
        XCTAssertEqual(sheet.files.map(\.fact), ["DATABASE_URL, STRIPE_KEY in plain text · copies stay in the vault"])
        XCTAssertEqual(sheet.notes.first?.mark, .failed)
        XCTAssertEqual(sheet.notes.first?.verbatim, ".env: no backup recorded")
        XCTAssertEqual(sheet.again, ["/h/billing/.env"], "Protect Again covers what came back")
        XCTAssertEqual(sheet.undo, [], "an undo has no Undo of its own")
    }

    // MARK: - Verify

    func testAVerifyThatPassedSaysSoAndKeepsTheOutputBehindTheDisclosure() {
        let sheet = ChangeSheet.verify(tool: "vercel", hint: "vercel whoami", status: 0, output: "dana", printsSecret: false)
        XCTAssertEqual(sheet.title, "vercel works")
        XCTAssertEqual(sheet.sentence, "vercel whoami finished without an error, using the key jit holds.")
        XCTAssertEqual(sheet.report, "dana")
        XCTAssertEqual(sheet.reportLabel, "vercel's output")
    }

    func testAFailedVerifyShowsTheToolsLastLineUnderTheFailure() {
        let sheet = ChangeSheet.verify(
            tool: "vercel", hint: "vercel whoami", status: 1, output: "Vercel CLI 39\nError: The token is not valid", printsSecret: false
        )
        XCTAssertEqual(sheet.title, "vercel's check failed")
        XCTAssertEqual(sheet.notes.first?.verbatim, "Error: The token is not valid")
    }

    /// gcloud's check prints an access token: no disclosure, no line under
    /// a failure. The app runs it with the output sent to /dev/null, and
    /// even an output passed in here is dropped.
    func testACheckThatPrintsASecretNeverKeepsWhatItPrinted() {
        let token = "ya29.not-a-real-token"
        for status: Int32 in [0, 1] {
            let sheet = ChangeSheet.verify(
                tool: "gcloud", hint: "gcloud auth application-default print-access-token", status: status, output: token,
                printsSecret: true
            )
            XCTAssertEqual(sheet.report, "", "exit \(status): nothing to disclose")
            XCTAssertNil(sheet.notes.first { $0.verbatim != nil }, "exit \(status): no line under the failure")
            XCTAssertFalse("\(sheet)".contains(token), "exit \(status): the value is nowhere in the sheet")
        }
    }

    func testGhsAccountsAreRowsTheActiveOneFirst() throws {
        let gh = try GhAuthStatus.parse(Data(#"""
        {"hosts":{"github.com":[
          {"state":"success","active":false,"host":"github.com","login":"dana-work","tokenSource":"keyring",
           "scopes":"repo, gist","gitProtocol":"https"},
          {"state":"success","active":true,"host":"github.com","login":"dana","tokenSource":"GH_TOKEN",
           "scopes":"repo, workflow","gitProtocol":"https"}
        ]}}
        """#.utf8))
        let sheet = ChangeSheet.verify(tool: "gh", hint: "gh auth status", status: 0, output: "…", printsSecret: false, gh: gh)
        XCTAssertEqual(sheet.title, "gh works · signed in as dana")
        XCTAssertEqual(sheet.sentence, "gh used the key jit gave it. 2 accounts are signed in on this Mac.")
        XCTAssertEqual(sheet.notes.map(\.name), ["dana · active", "dana-work"])
        XCTAssertEqual(sheet.notes.map(\.mark), [.done, .info])
        XCTAssertEqual(sheet.notes[0].fact, "github.com · key from jit · repo, workflow")
        XCTAssertEqual(sheet.notes[1].fact, "github.com · key in gh's keyring · repo, gist")
    }

    /// With --json gh exits 0 even when the key is rejected: `state` is the
    /// verdict.
    func testGhsStateIsTheVerdictNotItsExitStatus() {
        let gh = GhAuthStatus(hosts: ["github.com": [
            .init(state: "error", active: true, host: "github.com", login: "dana", tokenSource: "GH_TOKEN")
        ]])
        let sheet = ChangeSheet.verify(tool: "gh", hint: "gh auth status", status: 0, output: "", printsSecret: false, gh: gh)
        XCTAssertEqual(sheet.title, "gh's check failed")
        XCTAssertTrue(sheet.failed)
    }

    func testTheListingSaysWhichChecksPrintASecret() throws {
        let listing = try JSONDecoder().decode(ToolListing.self, from: Data(#"""
        {"tools":[{"tool":"gcloud","kind":"grant","catalog":true,"wrapped":false,"verify_hint":"x","verify_prints_secret":true},
                  {"tool":"gh","kind":"shim","catalog":true,"wrapped":false,"verify_hint":"gh auth status"}]}
        """#.utf8))
        XCTAssertEqual(listing.tool(named: "gcloud")?.verifyPrintsSecret, true)
        XCTAssertEqual(listing.tool(named: "gh")?.verifyPrintsSecret, false, "absent means it prints none")
    }

    // MARK: - Show Log and Doctor's plan

    func testTheServiceLogIsGroupedByDayNewestFirst() throws {
        let log = try ServiceLog.parse(Data(#"""
        {"path":"~/x/agent.log","entries":[
          {"date":"2026-09-30","time":"18:40","subjects":["/h/notes/.env"],"message":"python3 read .env","count":1,"level":"warn"},
          {"date":"2026-10-01","time":"13:56","message":"mounts now serving decoy content only","count":1,"level":"warn"},
          {"raw":"panic: runtime error"},
          {"date":"2026-10-01","time":"15:05","subjects":["/h/a/.env","/h/b/.env"],"message":"reader connected","count":2,"level":"ok"}
        ]}
        """#.utf8))
        let days = log.days(today: "2026-10-01", yesterday: "2026-09-30")
        XCTAssertEqual(days.map(\.label), ["Today", "Yesterday"])
        XCTAssertEqual(days[0].entries.map { $0.time ?? $0.raw ?? "" }, ["15:05", "panic: runtime error", "13:56"])
        XCTAssertTrue(log.plainText.contains("2026-10-01 15:05 reader connected (/h/a/.env, /h/b/.env)"))
    }

    func testDoctorsMigratePlanIsRowsNotJitsText() {
        let preview = MigratePreview(files: [
            .init(path: "/h/billing/.env", kind: "env", vars: [
                .init(name: "STRIPE_KEY", varClass: "secret", inVault: false),
                .init(name: "LOG_LEVEL", varClass: "setting", inVault: false, value: "debug")
            ]),
            .init(path: "/h/.mcp.json", kind: "mcp")
        ])
        let rows = PlanRow.migrate(preview)
        XCTAssertEqual(rows.map(\.name), ["STRIPE_KEY", "LOG_LEVEL", ".mcp.json"])
        XCTAssertEqual(rows.map(\.badge), ["Vault", "Stays as a setting", "Vault"])
        XCTAssertEqual(rows[1].detail, "debug", "a setting's value shows; a secret's never does")
        XCTAssertEqual(rows[0].detail, "")

        let undo = PlanRow.undo(UndoReport(dryRun: true, files: [
            .init(path: "/h/billing/.env", secrets: ["billing/STRIPE_KEY"]),
            .init(path: "/h/.aws/config", action: "remove")
        ]))
        XCTAssertEqual(undo.map(\.badge), ["Back in plain text", "Removed"])
        XCTAssertEqual(undo[0].detail, "STRIPE_KEY")
    }

    // MARK: - No printout comes back

    /// The app target has no tests of its own, so this reads its sources.
    /// The printout sheets are gone; a command's words reach the screen
    /// only under a failure row (`verbatim`) or behind ChangeSheetView's
    /// disclosure. Each of these was how a printout used to get there.
    func testNoWindowShowsACommandsPrintout() throws {
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JitPassApp")
        let files = try FileManager.default.contentsOfDirectory(atPath: app.path).filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty, "no sources found under \(app.path)")
        let banned = [
            "ResultSheet(", "DoctorOutputSheet", "DoctorOutput(", ".result(title:", "case result(", "showsOutput",
            "JitCLI.shell(", "Text(outcome.text", "Text(output", "view.string = plan"
        ]
        for file in files {
            let source = try String(contentsOf: app.appendingPathComponent(file), encoding: .utf8)
            for (number, line) in source.components(separatedBy: "\n").enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else {
                    continue
                }
                for word in banned where code.contains(word) {
                    XCTFail("\(file):\(number + 1) shows a command's printout (\(word))")
                }
                if code.contains("Text(sheet.report)"), file != "ChangeSheetView.swift" {
                    XCTFail("\(file):\(number + 1) draws a report outside the disclosure")
                }
            }
        }
    }
}
