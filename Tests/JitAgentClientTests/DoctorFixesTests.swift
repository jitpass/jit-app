// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// Doctor schema 2 (jit 1.9): the engine's `fixes` over the action's
/// backticks, with the older report's parsing kept for a jit before it.
final class DoctorFixesTests: XCTestCase {
    /// Trimmed from a real jit 1.9.0 report.
    private let json = #"""
    {"schema_version":2,"tool":{"version":"1.9.0"},"ok":false,
     "problems":[{"kind":"missing","profile":"k8s","scope":"global","variable":"CERT","path":"k8s/CERT","detail":"",
       "action":"`jit vault set k8s/CERT`, or `jit migrate <path>` to convert the file it came from",
       "fixes":[{"command":"jit vault set k8s/CERT","argv":["vault","set","k8s/CERT"],"destructive":false,"presence":true},
                {"command":"jit migrate <path>","argv":["migrate","<path>"],"destructive":false,"presence":false,"needs":"<path>"}]}],
     "warnings":[
      {"kind":"origin_gone","path":"~/token.txt","detail":"token was migrated from ~/token.txt, which no longer exists on disk",
       "action":"nothing to do: the vault is where these live now","groups":["token"],"profiles":["token","mcp-okta"]},
      {"kind":"legacy_envelope","detail":"11 secrets use an old format.",
       "action":"`jit vault export <file>` then `jit vault import <file>` re-encrypts every secret",
       "fixes":[{"command":"jit vault export <file>","argv":["vault","export","<file>"],
                 "destructive":false,"presence":true,"needs":"<file>"},
                {"command":"jit vault import <file>","argv":["vault","import","<file>"],
                 "destructive":true,"presence":true,"needs":"<file>"}]},
      {"kind":"service","detail":"The background service is running a different build than this CLI.",
       "action":"`jit service restart` to move it to the current binary",
       "fixes":[{"command":"jit service restart","argv":["service","restart"],"destructive":false,"presence":false}]},
      {"kind":"brand_new","detail":"something new","action":"`jit vault frobnicate --all` or `jit vault list`",
       "fixes":[{"command":"jit vault frobnicate --all","argv":["vault","frobnicate","--all"]},
                {"command":"jit vault list","argv":["vault","list"],"destructive":false,"presence":false}]},
      {"kind":"stray","detail":"an action whose backticks the engine chose not to offer","action":"`jit vault rm stray`"}]}
    """#

    private func report() throws -> DoctorReport {
        try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
    }

    private func warning(_ kind: String) throws -> DoctorItem {
        try XCTUnwrap(report().warnings.first { $0.kind == kind })
    }

    func testDecodesSchemaFixesGroupsAndProfiles() throws {
        let r = try report()
        XCTAssertEqual(r.schemaVersion, 2)
        XCTAssertEqual(r.problems[0].fixes?.count, 2)
        XCTAssertEqual(r.problems[0].fixes?[1].needs, "<path>")
        XCTAssertEqual(r.problems[0].fixes?[0].presence, true)
        let origin = try warning("origin_gone")
        XCTAssertEqual(origin.groups, ["token"])
        XCTAssertEqual(origin.profiles, ["token", "mcp-okta"])
        XCTAssertEqual(origin.fixes, [], "schema 2 without fixes means none, not 'parse the prose'")
    }

    /// A fix the engine did not classify is destructive.
    func testUnknownFixIsDestructive() throws {
        let fix = try JSONDecoder().decode(DoctorFix.self, from: Data(#"{"command":"jit vault x","argv":["vault","x"]}"#.utf8))
        XCTAssertTrue(fix.destructive)
        let actions = try DoctorAdvice.actions(for: warning("brand_new"))
        XCTAssertEqual(actions.map(\.command), ["jit vault frobnicate --all", "jit vault list"])
        XCTAssertEqual(actions.map(\.destructive), [true, false], "the engine's word, not a prefix guess")
    }

    /// In a schema 2 report the backticks are prose: a command the engine
    /// did not put in `fixes` gets no button.
    func testFixesTakePrecedenceOverBackticks() throws {
        let stray = try warning("stray")
        XCTAssertEqual(stray.commands, [])
        XCTAssertEqual(DoctorAdvice.actions(for: stray), [])
        var old = stray
        old.fixes = nil
        XCTAssertEqual(old.commands, ["jit vault rm stray"], "an older report still parses its backticks")
        XCTAssertTrue(DoctorAdvice.actions(for: old).first?.destructive ?? false)
    }

    /// Kind builders keep their titles; a fix they run can only add caution.
    func testBuildersKeepTitlesAndTakeTheEnginesCaution() throws {
        let missing = try DoctorAdvice.actions(for: report().problems[0])
        XCTAssertEqual(missing.map(\.title), ["Set Value", "Migrate a File", "Remove Variable"])
        XCTAssertEqual(missing.map(\.destructive), [false, false, true], "only the drop confirms")
        XCTAssertTrue(missing[0].presence, "vault set asks for Touch ID itself")
        let reencrypt = try DoctorAdvice.actions(for: warning("legacy_envelope"))
        XCTAssertEqual(reencrypt.map(\.title), ["Re-encrypt"])
        XCTAssertTrue(reencrypt[0].destructive, "the import step overwrites, per the engine")
        let text = DoctorAdvice.confirmation(for: reencrypt[0])
        XCTAssertTrue(text.contains("overwritten"), text)
        XCTAssertTrue(text.hasSuffix("Touch ID follows."), text)
        let service = try DoctorAdvice.actions(for: warning("service"))
        XCTAssertEqual(service.map(\.title), ["Restart Service"])
        XCTAssertFalse(service[0].destructive)
    }

    func testOriginGoneRowNamesItsProfilesAndOffersNothing() throws {
        let origin = try warning("origin_gone")
        XCTAssertEqual(DoctorAdvice.rowText(origin), "token · from ~/token.txt · used by token, mcp-okta")
        XCTAssertEqual(DoctorAdvice.actions(for: origin), [])
    }

    /// A report from jit 1.8 (schema 1, no fixes) renders as before.
    func testOlderReportFallsBackToBackticks() throws {
        let old = #"""
        {"schema_version":1,"ok":false,"problems":[],
         "warnings":[{"kind":"brand_new","detail":"x","action":"`jit vault frobnicate --all` or `jit vault list`"}]}
        """#
        let r = try JSONDecoder().decode(DoctorReport.self, from: Data(old.utf8))
        XCTAssertNil(r.warnings[0].fixes)
        let actions = DoctorAdvice.actions(for: r.warnings[0])
        XCTAssertEqual(actions.map(\.command), ["jit vault frobnicate --all", "jit vault list"])
        XCTAssertEqual(actions.map(\.destructive), [false, false], "1.8 behaviour: only known deleting prefixes")
        let unversioned = try JSONDecoder().decode(DoctorReport.self, from: Data(#"{"ok":true}"#.utf8))
        XCTAssertNil(unversioned.schemaVersion)
    }

    func testStepMatchingSeesThroughTildesAndChains() {
        let fix = DoctorFix(command: "jit unmount ~/a/.env", argv: ["unmount", "/Users/me/a/.env"], destructive: true, presence: true)
        let terminal = DoctorAction("Unmount", "jit unmount ~/a/.env")
        XCTAssertTrue(DoctorAdvice.reconciled(terminal, with: [fix]).destructive)
        let chained = DoctorAction("X", "jit vault export <file> && jit vault import <file>")
        let importFix = DoctorFix(command: "jit vault import <file>", argv: ["vault", "import", "<file>"], destructive: true)
        XCTAssertTrue(DoctorAdvice.reconciled(chained, with: [importFix]).destructive)
        let careful = DoctorAction("Y", "jit vault rm a", destructive: true)
        let lenient = DoctorFix(command: "jit vault rm a", argv: ["vault", "rm", "a"], destructive: false)
        XCTAssertTrue(DoctorAdvice.reconciled(careful, with: [lenient]).destructive, "never less careful than the builder")
    }
}
