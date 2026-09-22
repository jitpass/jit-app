// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// One card per agent, each row one fact in the numbers Findings and the
/// audit hold. The digest it replaces counted one finding type and said
/// "all set" over 34 copies (2026-09-22).
final class AgentCardTests: XCTestCase {
    private func finding(
        _ id: String,
        type: String,
        path: String,
        key: String? = nil,
        agent: String? = "Claude Code",
        area: String? = "transcripts"
    ) -> String {
        var fields = [
            #""record_type":"finding""#, #""record_id":"\#(id)""#, #""finding_type":"\#(type)""#, #""severity":"high""#,
            #""file_path":"\#(path)""#, #""line":7"#, #""evidence":"value matches Stripe Live Secret Key's known token format""#,
            #""remedy":"manual""#, #""archived":false"#, #""test_fixture":false"#
        ]
        if let key {
            fields.append(#""key_name":"\#(key)""#)
        }
        if let agent {
            fields.append(#""agent":"\#(agent)""#)
        }
        if let area {
            fields.append(#""cache_area":"\#(area)""#)
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func report(_ lines: [String]) throws -> ScanReport {
        let summary = #"{"record_type":"scan_summary","total_findings":0,"risk_level":"low","exposure_score":0,"#
            + #""secrets_total":0,"secrets_protected":0,"secrets_migratable":0,"files_scanned":10,"deep":true}"#
        return try ScanReport.parse(Data((lines + [summary]).joined(separator: "\n").utf8))
    }

    private func input(
        exposure: AgentExposure? = AgentExposure(), key: ToolKeyState = .none, consent: Bool? = true,
        activity: AgentActivity? = AgentActivity(), newCopies: Int = 0, mcp: Int = 0, redacts: Bool = false
    ) -> AgentCard.Input {
        AgentCard.Input(
            tool: "claude", label: "Claude Code", key: key, wrapped: false, healthy: true, stateLabel: "shim is missing",
            exposure: exposure, newCopies: newCopies, protectedFiles: 3, mcpKeysInTheOpen: mcp, grantUntil: nil,
            consent: consent, activity: activity, redactsAfterScan: redacts, home: "/Users/me"
        )
    }

    /// Meni's Mac: 34 copies of 4 vaulted entries and 17 tokens in Claude
    /// Code's files. Every one counts, whatever its finding type.
    func testExposureCountsEveryFindingInTheAgentsFiles() throws {
        var lines: [String] = []
        for index in 0 ..< 30 {
            lines.append(finding(
                "g\(index)",
                type: "vault_copy",
                path: "/Users/me/.claude/projects/p/\(index).jsonl",
                key: "google/ADMIN_SUBJECT"
            ))
        }
        lines.append(finding(
            "h1",
            type: "vault_copy",
            path: "/Users/me/.claude/history.jsonl",
            key: "hibob/SERVICE_USER_ID",
            area: "local store"
        ))
        lines.append(finding("c1", type: "agent_cached_secret", path: "/Users/me/.claude/file-history/a", area: "edit history"))
        for index in 0 ..< 9 {
            lines.append(finding("t\(index)", type: "exposed_secret", path: "/Users/me/.claude/projects/j/one.jsonl"))
        }
        for index in 9 ..< 17 {
            lines.append(finding("t\(index)", type: "exposed_secret", path: "/Users/me/.claude/projects/j/two.jsonl"))
        }
        lines.append(finding("w1", type: "vault_copy", path: "/Users/me/rules/a.json", key: "wiz/WIZ_CLIENT_SECRET", agent: nil, area: nil))
        lines.append(finding("x1", type: "exposed_secret", path: "/Users/me/.codex/x.jsonl", agent: "Codex CLI"))
        let exposure = try report(lines).agentExposure("Claude Code")
        XCTAssertEqual(exposure.copies, 32)
        XCTAssertEqual(exposure.vaultSecrets, 2)
        XCTAssertEqual(exposure.copyFiles, 32)
        XCTAssertEqual(exposure.tokens, 17)
        XCTAssertEqual(exposure.tokenFiles, 2)
        XCTAssertEqual(exposure.tokenPaths, ["/Users/me/.claude/projects/j/one.jsonl", "/Users/me/.claude/projects/j/two.jsonl"])
        XCTAssertEqual(exposure.areas, ["transcripts", "local store", "edit history"])
        XCTAssertEqual(try report(lines).agentExposure("Codex CLI").total, 1, "another agent's file is that agent's")
        XCTAssertTrue(try report([lines[0]]).agentExposure("Cursor").isEmpty)
    }

    func testActivityIsCountedFromWhatTheAgentLaunched() throws {
        let json = """
        {"commands":[
          {"unix_nano":1,"command":"jit run -- gh pr list","launched_by":"claude","success":true},
          {"unix_nano":2,"command":"jit scan","launched_by":"/opt/homebrew/bin/claude --resume","success":true},
          {"unix_nano":3,"command":"jit status","launched_by":"JitPass","success":true}],
         "auth_events":[
          {"unix_time":4,"kind":"use","op":"use","launched_by":"claude","labels":["wiz/WIZ_CLIENT_SECRET"]},
          {"unix_time":5,"kind":"serve","op":"decoy","by":"/usr/bin/python3 x.py","launched_by":"claude","count":2},
          {"unix_time":6,"kind":"serve","op":"decoy","by":"claude","undelivered":true},
          {"unix_time":7,"kind":"serve","op":"real","by":"gh","launched_by":"claude"},
          {"unix_time":8,"kind":"approved","by":"gh","launched_by":"claude"},
          {"unix_time":9,"kind":"denied","launched_by":"codex"},
          {"unix_time":10,"kind":"unlock","by":"JitPass"}]}
        """
        let activity = try JSONDecoder().decode(AuditReport.self, from: Data(json.utf8)).agentActivity(tool: "claude")
        XCTAssertEqual(activity, AgentActivity(runs: 2, realValues: 2, decoyReads: 2, prompts: 1))
        XCTAssertEqual(AuditReport.program("/opt/homebrew/bin/claude --resume"), "claude")
        XCTAssertNil(AuditReport.program(nil))
    }

    func testCopiesInItsFilesAreRedAndTheHeaderSaysSo() {
        var exposure = AgentExposure()
        exposure.copies = 32; exposure.vaultSecrets = 4; exposure.copyFiles = 31; exposure.tokens = 17; exposure.tokenFiles = 3
        let card = AgentCard.make(input(exposure: exposure, activity: AgentActivity(runs: 44), newCopies: 2))
        XCTAssertEqual(card.state, .red)
        XCTAssertEqual(card.todo, "Claude Code's files hold copies of 4 vaulted secrets and 17 other tokens")
        XCTAssertEqual(card.inFiles, "copies of 4 vaulted secrets in 31 files · 17 tokens by format in 3 files")
        XCTAssertEqual(card.since, "Since the last scan: 2 new copies in its files · 44 runs through jit · nothing asked of you.")
        XCTAssertTrue(card.offersClean)
        XCTAssertEqual(card.redactCount, 17)
        XCTAssertEqual(card.thisWeek, "44 runs through jit · 0 real values disclosed · 0 decoy reads · 0 prompts")

        var tokensOnly = AgentExposure()
        tokensOnly.tokens = 1; tokensOnly.tokenFiles = 1
        let tokens = AgentCard.make(input(exposure: tokensOnly))
        XCTAssertEqual(tokens.todo, "Claude Code's files hold 1 token")
        XCTAssertFalse(tokens.offersClean)
    }

    func testAskingOffAndAnOpenKeyAreAmberAndCleanIsGreen() {
        let off = AgentCard.make(input(consent: false))
        XCTAssertEqual(off.state, .amber)
        XCTAssertEqual(
            off.canReach,
            "3 protected files through jit · a real value goes to it without asking you · no MCP key in the open · no grant"
        )
        XCTAssertNil(off.todo)

        let on = AgentCard.make(input(key: .found("/Users/me/.cursor/settings.json")))
        XCTAssertEqual(
            on.canReach,
            "3 protected files through jit · a real value goes to it only after your Touch ID · no MCP key in the open · no grant"
        )
        XCTAssertEqual(on.key, "in the open, ~/.cursor/settings.json")
        XCTAssertEqual(on.state, .amber)

        let clean = AgentCard.make(input())
        XCTAssertEqual(clean.state, .green)
        XCTAssertEqual(clean.inFiles, "no copy of a secret in its files")
        XCTAssertEqual(clean.key, "none on this Mac · nothing for jit to move")
        XCTAssertEqual(clean.redactFact, "off · tokens it records stay until you redact them by hand")
        XCTAssertTrue(AgentCard.make(input(redacts: true)).redactFact.hasPrefix("on ·"))
    }

    func testUncheckedFactsLowerNothingAndSaySo() {
        let card = AgentCard.make(input(exposure: nil, key: .unknown, consent: nil, activity: nil))
        XCTAssertEqual(card.state, .green)
        XCTAssertEqual(card.inFiles, "not searched yet")
        XCTAssertEqual(card.thisWeek, "not read yet")
        XCTAssertEqual(card.key, "not checked yet")
        XCTAssertEqual(card.since, "Not searched yet: a whole-Mac scan fills in its files.")
        XCTAssertTrue(card.canReach.contains("the service is not running"))
    }
}
