// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The Findings header says what to do in the cards' own numbers, one
/// line per tier with something in it. Every number here is one a card
/// below the header also shows.
final class ScanTodoTests: XCTestCase {
    private func finding(
        _ id: String, type: String = "exposed_secret", path: String, line: Int = 1, key: String? = nil,
        evidence: String = "value matches AWS Access Key ID's known token format", remedy: String = "manual",
        agent: String? = nil, area: String? = nil, fixture: Bool = false
    ) -> String {
        var fields = [
            #""record_type":"finding""#, #""record_id":"\#(id)""#, #""finding_type":"\#(type)""#, #""severity":"high""#,
            #""file_path":"\#(path)""#, #""line":\#(line)"#, #""evidence":"\#(evidence)""#, #""remedy":"\#(remedy)""#,
            #""archived":false"#, #""test_fixture":\#(fixture)"#
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

    private func report(_ lines: [String], deep: Bool = false) throws -> ScanReport {
        let summary = #"{"record_type":"scan_summary","total_findings":0,"risk_level":"low","exposure_score":0,"#
            + #""secrets_total":26,"secrets_protected":10,"secrets_migratable":0,"files_scanned":12305"# + (deep ? #","deep":true"# : "") +
            "}"
        return try ScanReport.parse(Data((lines + [summary]).joined(separator: "\n").utf8))
    }

    private func vaultCopy(_ id: String, _ key: String, _ path: String, agent: String? = nil) -> String {
        finding(id, type: "vault_copy", path: path, line: 7, key: key,
                evidence: "an exact copy of the vaulted secret \(key)" + (agent.map { ", kept by \($0)" } ?? ""), agent: agent,
                area: agent.map { _ in "transcripts" })
    }

    private func shape(_ id: String, _ path: String) -> String {
        finding(
            id,
            path: path,
            line: 214,
            evidence: "value matches Stripe Live Secret Key's known token format (found in Claude Code's transcripts)",
            agent: "Claude Code",
            area: "transcripts"
        )
    }

    /// Meni's Mac on 22 Sep: 35 vault copies of 4 entries in 32 files, 17
    /// tokens by format in 2 transcripts, 8 fixtures. The header said
    /// "10 of 26 secrets protected" and nothing on it was a list.
    func testOneLinePerCardInTheCardsOwnNumbers() throws {
        var lines: [String] = []
        for index in 0 ..< 30 {
            lines.append(vaultCopy(
                "g\(index)",
                "google/ADMIN_SUBJECT",
                "/Users/me/.claude/projects/p/\(index).jsonl",
                agent: "Claude Code"
            ))
        }
        lines.append(vaultCopy("g30", "google/ADMIN_SUBJECT", "/Users/me/.claude/projects/p/0.jsonl", agent: "Claude Code"))
        lines.append(vaultCopy("h1", "hibob/SERVICE_USER_ID", "/Users/me/.claude/history.jsonl", agent: "Claude Code"))
        lines.append(vaultCopy("w1", "wiz/WIZ_CLIENT_SECRET", "/Users/me/Security-Ops/rules/a.json"))
        lines.append(vaultCopy("w2", "wiz/WIZ_CLIENT_SECRET", "/Users/me/Security-Ops/rules/b.json"))
        lines.append(vaultCopy("s1", "sample/SAMPLE_ONE", "/Users/me/.claude/projects/p/0.jsonl", agent: "Claude Code"))
        for index in 0 ..< 9 {
            lines.append(shape("t\(index)", "/Users/me/.claude/projects/j/one.jsonl"))
        }
        for index in 9 ..< 17 {
            lines.append(shape("t\(index)", "/Users/me/.claude/projects/j/two.jsonl"))
        }
        lines.append(finding("x1", path: "/Users/me/app/x_test.go", fixture: true))
        let todos = try report(lines, deep: true).todos(deepAvailable: true)

        XCTAssertEqual(todos.map(\.text), [
            "4 still have plaintext copies in 33 files",
            "17 flagged lines sit in 2 files of Claude Code's transcripts"
        ])
        XCTAssertEqual(todos.map(\.verb), ["clear the copies", "redact them"])
        XCTAssertEqual(todos[0].sentence, "4 still have plaintext copies in 33 files · clear the copies")
        XCTAssertEqual(todos.map(\.action), [.show(.vaultCopies), .show(.agentCaches)])
        XCTAssertNil(todos.first { $0.action == .deepScan }, "a deep scan looked; it is not told to look")
    }

    func testEveryTierHasItsLineAndItsVerb() throws {
        let r = try report([
            finding("m1", path: "/Users/me/app/.env", key: "API_KEY", evidence: "plaintext secret", remedy: "migrate"),
            finding("n1", type: "shell_history_secret", path: "/Users/me/.zsh_history", line: 88),
            finding("n2", type: "shell_history_secret", path: "/Users/me/.bash_history", line: 12),
            finding(
                "c1",
                type: "agent_cached_secret",
                path: "/Users/me/.claude/file-history/a",
                evidence: "copy of API_KEY",
                agent: "Claude Code",
                area: "edit history"
            )
        ])
        let todos = r.todos(deepAvailable: true)
        XCTAssertEqual(todos.map(\.text), [
            "1 file holds a secret jit can move into the vault",
            "2 files hold secrets only you can fix",
            "1 copy of a vaulted secret sits in Claude Code's edit history",
            "Copies of your vaulted secrets are not looked for by a regular scan"
        ])
        XCTAssertEqual(todos.map(\.verb), ["protect it", "rotate or move them", "clean the caches", "run a deep scan"])
        XCTAssertEqual(todos.last?.action, .deepScan)
    }

    func testNothingInTheOpenIsSaidOnce() throws {
        let clean = try report([finding("x1", path: "/Users/me/app/x_test.go", fixture: true)])
        XCTAssertEqual(clean.todos(deepAvailable: false).map(\.text), ["Nothing in the open."])
        XCTAssertEqual(clean.todos(deepAvailable: false).first?.action, ScanTodo.Action.none)
        XCTAssertEqual(
            clean.todos(deepAvailable: true).map(\.verb), [nil, "run a deep scan"],
            "clean, but a regular scan: the vault has secrets it did not look for"
        )
        let carried = try report([vaultCopy("g1", "google/ADMIN_SUBJECT", "/Users/me/.claude/history.jsonl", agent: "Claude Code")])
        XCTAssertEqual(
            carried.todos(deepAvailable: true).map(\.verb), ["clear the copies"],
            "a regular run carrying the deep scan's copies is not told to look for them"
        )
    }
}
