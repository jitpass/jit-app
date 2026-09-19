// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// Doctor's ownership kinds (jit 2.0): what the window titles them, what
/// each row says, and which buttons they get. Missing profiles get none,
/// a missing pointer Set Value, profiles recording no live config one
/// Attach per config on the group, a profile no known tool uses Remove
/// Profile.
final class DoctorOwnershipTests: XCTestCase {
    /// Trimmed from a real `jit doctor --format json` of jit main (to be
    /// 2.0), home renamed: two findings of each ownership kind. That build
    /// still said launcher_broken, owner_gone, no_owner, unlaunched and
    /// `profile adopt`; the kinds, commands and details are renamed here
    /// to what 2.0 ships.
    private let json = #"""
    {"schema_version":2,"tool":{"version":"v1.9.1"},"ok":false,"problems":[{"kind":"profile_missing",
    "profile":"aws-dev","detail":"~/.aws/config [profile dev] names profile aws-dev, which no jit store holds",
    "action":"no such jit profile, so aws --profile dev fails; mint it again, or delete that [profile] block",
    "file":"/Users/me/.aws/config","launchers":[{"kind":"aws","file":"/Users/me/.aws/config","detail":"[profile dev]",
    "profile":"aws-dev"}]},{"kind":"profile_missing","profile":"aws-admin",
    "detail":"~/.aws/config [profile admin] names profile aws-admin, which no jit store holds",
    "action":"no such jit profile, so aws --profile admin fails; mint it again, or delete that [profile] block",
    "file":"/Users/me/.aws/config","launchers":[{"kind":"aws","file":"/Users/me/.aws/config","detail":"[profile admin]",
    "profile":"aws-admin"}]},{"kind":"pointer_missing","path":"jitpass-playground-bak/API_KEY",
    "detail":"~/Documents/jitpass-playground/.env.bak points at jitpass-playground-bak/API_KEY, which isn't in the vault",
    "action":"`jit vault set jitpass-playground-bak/API_KEY`",
    "fixes":[{"command":"jit vault set jitpass-playground-bak/API_KEY","argv":["vault","set",
    "jitpass-playground-bak/API_KEY"],"destructive":false,"presence":true}],
    "file":"/Users/me/Documents/jitpass-playground/.env.bak"},{"kind":"pointer_missing",
    "path":"wrap-clisso/acme-client-secret",
    "detail":"~/.clisso.yaml points at wrap-clisso/acme-client-secret, which isn't in the vault",
    "action":"`jit vault set wrap-clisso/acme-client-secret`",
    "fixes":[{"command":"jit vault set wrap-clisso/acme-client-secret","argv":["vault","set",
    "wrap-clisso/acme-client-secret"],"destructive":false,"presence":true}],"file":"/Users/me/.clisso.yaml"}],
    "warnings":[{"kind":"config_deleted","profile":"mcp-caido","scope":"global",
    "path":"/Users/me/.jit/profiles/mcp-caido.yaml",
    "detail":"recorded config ~/Documents/ai_security_workspace/.mcp.json is deleted; now started by ~/Security-Ops/.mcp.json",
    "action":"`jit profile attach ~/Security-Ops/.mcp.json`",
    "fixes":[{"command":"jit profile attach ~/Security-Ops/.mcp.json","argv":["profile","attach",
    "/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],
    "config":"/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"launchers":[{"kind":"mcp",
    "file":"/Users/me/Security-Ops/.mcp.json","detail":"caido","profile":"mcp-caido"},{"kind":"mcp",
    "file":"/Users/me/Security-Ops/.mcp.json","detail":"caido","profile":"mcp-caido","layer":1}]},{"kind":"config_deleted",
    "profile":"mcp-okta","scope":"global","path":"/Users/me/.jit/profiles/mcp-okta.yaml",
    "detail":"recorded config ~/Documents/ai_security_workspace/.mcp.json is deleted; now started by ~/Security-Ops/.mcp.json",
    "action":"`jit profile attach ~/Security-Ops/.mcp.json`",
    "fixes":[{"command":"jit profile attach ~/Security-Ops/.mcp.json","argv":["profile","attach",
    "/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],
    "config":"/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"launchers":[{"kind":"mcp",
    "file":"/Users/me/Security-Ops/.mcp.json","detail":"okta-mcp-server","profile":"mcp-okta","layer":1}]},
    {"kind":"config_not_recorded","profile":"mcp-google-workspace","scope":"global",
    "path":"/Users/me/.jit/profiles/mcp-google-workspace.yaml",
    "detail":"no config recorded; started by ~/Security-Ops/.mcp.json",
    "action":"`jit profile attach ~/Security-Ops/.mcp.json`",
    "fixes":[{"command":"jit profile attach ~/Security-Ops/.mcp.json","argv":["profile","attach",
    "/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],
    "config":"/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "launchers":[{"kind":"mcp","file":"/Users/me/Security-Ops/.mcp.json","detail":"google-workspace-investigate",
    "profile":"mcp-google-workspace","layer":1}]},{"kind":"config_not_recorded","profile":"mcp-urlscan","scope":"global",
    "path":"/Users/me/.jit/profiles/mcp-urlscan.yaml",
    "detail":"no config recorded; started by ~/Security-Ops/.mcp.json",
    "action":"`jit profile attach ~/Security-Ops/.mcp.json`",
    "fixes":[{"command":"jit profile attach ~/Security-Ops/.mcp.json","argv":["profile","attach",
    "/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],
    "config":"/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "launchers":[{"kind":"mcp","file":"/Users/me/Security-Ops/.mcp.json","detail":"urlscan","profile":"mcp-urlscan"}]},
    {"kind":"no_known_tool","profile":"k8s-docker-desktop","scope":"global",
    "path":"/Users/me/.jit/profiles/k8s-docker-desktop.yaml","detail":"no known tool; 2 secrets, both missing",
    "action":"`jit profile rm k8s-docker-desktop` if you no longer use it",
    "fixes":[{"command":"jit profile rm k8s-docker-desktop","argv":["profile","rm","k8s-docker-desktop"],
    "destructive":true,"presence":true}],"secrets":2,"secrets_missing":2},{"kind":"no_known_tool","profile":"token",
    "scope":"global","path":"/Users/me/.jit/profiles/token.yaml","detail":"no known tool; 1 secret",
    "action":"`jit profile rm token` if you no longer use it","fixes":[{"command":"jit profile rm token",
    "argv":["profile","rm","token"],"destructive":true,"presence":true}],"secrets":1,"origin":"/Users/me/token.txt"}]}
    """#

    private func report() throws -> DoctorReport {
        try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
    }

    private func items(_ kind: String) throws -> [DoctorItem] {
        let r = try report()
        return (r.problems + r.warnings).filter { $0.kind == kind }
    }

    private func group(_ kind: String) throws -> DoctorGroup {
        let r = try report()
        return try XCTUnwrap((r.problemGroups + r.warningGroups).first { $0.kind == kind })
    }

    private func home(_ path: String) -> String {
        DoctorAdvice.homePath(path)
    }

    func testDecodesTheOwnershipFields() throws {
        let r = try report()
        XCTAssertEqual(r.problems.map(\.kind), ["profile_missing", "profile_missing", "pointer_missing", "pointer_missing"])
        let missing = r.problems[0]
        XCTAssertEqual(missing.file, "/Users/me/.aws/config")
        XCTAssertEqual(
            missing.launchers,
            [DoctorLauncher(kind: "aws", file: "/Users/me/.aws/config", detail: "[profile dev]", profile: "aws-dev")]
        )
        XCTAssertEqual(missing.fixes, [], "a hand edit: the engine offers no command")
        let caido = try XCTUnwrap(items("config_deleted").first)
        XCTAssertEqual(caido.config, "/Users/me/Security-Ops/.mcp.json")
        XCTAssertEqual(caido.configs, ["/Users/me/Security-Ops/.mcp.json"])
        XCTAssertEqual(caido.owners, ["/Users/me/Documents/ai_security_workspace/.mcp.json"])
        XCTAssertEqual(caido.launchers?.map(\.layer), [nil, 1])
        let unused = try items("no_known_tool")
        XCTAssertEqual(unused.map(\.secrets), [2, 1])
        XCTAssertEqual(unused.map(\.secretsMissing), [2, nil])
        XCTAssertEqual(unused.map(\.origin), [nil, "/Users/me/token.txt"])
        XCTAssertEqual(Set((r.problems + r.warnings).map(\.id)).count, r.problems.count + r.warnings.count)
    }

    /// A pre-release jit 2.0 said launcher_broken, owner_gone, no_owner and
    /// unlaunched, and `jit profile adopt`: those read as the new kinds,
    /// with the same titles, rows and buttons, and the button runs attach.
    func testOldKindNamesDecodeAsTheNewOnes() throws {
        var old = json
        for (new, was) in [
            ("\"profile_missing\"", "\"launcher_broken\""), ("\"config_deleted\"", "\"owner_gone\""),
            ("\"config_not_recorded\"", "\"no_owner\""), ("\"no_known_tool\"", "\"unlaunched\""),
            ("jit profile attach", "jit profile adopt"), ("\"profile\",\"attach\"", "\"profile\",\"adopt\"")
        ] {
            old = old.replacingOccurrences(of: new, with: was)
        }
        XCTAssertFalse(old.contains("attach") || old.contains("config_deleted"), "the fixture is the old shape")
        let r = try JSONDecoder().decode(DoctorReport.self, from: Data(old.utf8))
        XCTAssertEqual(Set((r.problems + r.warnings).map(\.kind)), [
            "profile_missing", "pointer_missing", "config_deleted", "config_not_recorded", "no_known_tool"
        ])
        XCTAssertEqual(r.warningGroups.map(\.title), [
            "Profiles recording a deleted config", "Profiles with no config recorded", "No known tool"
        ])
        let attach = try XCTUnwrap(r.warningGroups.first).groupActions
        XCTAssertEqual(attach.map(\.title), ["Attach 4"])
        XCTAssertEqual(attach.first?.argv, [["profile", "attach", "--yes", "/Users/me/Security-Ops/.mcp.json"]])
        XCTAssertEqual(attach.first?.planned, .attach(config: "/Users/me/Security-Ops/.mcp.json"))
        XCTAssertEqual(DoctorAdvice.currentKind("mount_stale"), "mount_stale", "every other kind as it is")
    }

    func testTitlesAndNotes() throws {
        let kinds = ["profile_missing", "pointer_missing", "config_deleted", "config_not_recorded", "no_known_tool"]
        XCTAssertEqual(try kinds.map { try group($0).title }, [
            "Missing profiles", "Missing pointed-to secrets", "Profiles recording a deleted config",
            "Profiles with no config recorded", "No known tool"
        ])
        XCTAssertEqual(try kinds.map { try group($0).note ?? "" }, [
            "A config names a jit profile that doesn't exist, so that tool fails.",
            "A file points at a secret the vault doesn't hold, so the tool that reads it gets nothing.",
            "The config they record is deleted, and another one starts their tools now. "
                + "Attach records that config instead; no secret changes.",
            "A config starts their tools, but none is recorded for them. Attach records it; no secret changes.",
            "Nothing jit can see uses these. It can't see scripts or aliases, so remove one only if you no longer use it."
        ])
    }

    /// A record group's shared facts are two lines, as `jit doctor` prints
    /// them, each naming its file: one sentence of two paths wrapped
    /// mid-path. A config-not-recorded group has only the config.
    func testRecordFactsAreOneLineEach() throws {
        XCTAssertEqual(try group("config_deleted").facts, [
            DoctorFact(
                "Recorded config \(home("/Users/me/Documents/ai_security_workspace/.mcp.json")) is deleted",
                path: "/Users/me/Documents/ai_security_workspace/.mcp.json"
            ),
            DoctorFact("Now started by \(home("/Users/me/Security-Ops/.mcp.json"))", path: "/Users/me/Security-Ops/.mcp.json")
        ])
        XCTAssertEqual(try group("config_not_recorded").facts, [
            DoctorFact("Started by \(home("/Users/me/Security-Ops/.mcp.json"))", path: "/Users/me/Security-Ops/.mcp.json")
        ])
        XCTAssertEqual(try group("no_known_tool").facts, [])
        XCTAssertEqual(try group("profile_missing").facts, [])
    }

    func testRowText() throws {
        let missing = try group("profile_missing")
        XCTAssertEqual(missing.items.map(missing.rowText), [
            home("/Users/me/.aws/config") + " [profile dev] names aws-dev",
            home("/Users/me/.aws/config") + " [profile admin] names aws-admin"
        ])
        let pointers = try group("pointer_missing")
        XCTAssertEqual(pointers.rowText(pointers.items[1]), home("/Users/me/.clisso.yaml") + " · wrap-clisso/acme-client-secret")
        XCTAssertTrue(DoctorAdvice.rowIsPath(pointers.items[1]))
        XCTAssertEqual(pointers.runs.map(\.note), [nil])
        let deleted = try group("config_deleted")
        XCTAssertEqual(
            deleted.items.map(deleted.rowText), ["mcp-caido · tool caido", "mcp-okta · tool okta-mcp-server"],
            "the tool once, though caido uses it at two layers; the shared facts are on the note"
        )
        let unrecorded = try group("config_not_recorded")
        XCTAssertEqual(unrecorded.items.map(unrecorded.rowText), [
            "mcp-google-workspace · tool google-workspace-investigate", "mcp-urlscan · tool urlscan"
        ])
        let unused = try group("no_known_tool")
        XCTAssertEqual(unused.items.map(unused.rowText), [
            "k8s-docker-desktop · 2 secrets, both missing", "token · 1 secret · made from \(home("/Users/me/token.txt")), now gone"
        ])
    }

    /// Several servers are named together; a row whose tools aren't MCP
    /// servers is the profile alone.
    func testToolsPhrase() {
        let mcp = { (name: String) in DoctorLauncher(kind: "mcp", file: "/c", detail: name) }
        XCTAssertEqual(DoctorAdvice.toolsPhrase([mcp("a"), mcp("b"), mcp("a"), mcp("c")]), "tools a, b and c")
        XCTAssertNil(DoctorAdvice.toolsPhrase([DoctorLauncher(kind: "aws", file: "/c", detail: "[profile x]")]))
        XCTAssertNil(DoctorAdvice.toolsPhrase(nil))
    }

    /// Rows whose configs differ each say their own; the note says nothing
    /// it could get wrong for some of them.
    func testRecordRowsThatDifferNameTheirConfigs() throws {
        var rows = try items("config_not_recorded")
        rows[1].configs = ["/Users/me/other/.mcp.json"]
        rows[1].config = "/Users/me/other/.mcp.json"
        rows[1].fixes = [DoctorFix(
            command: "jit profile attach ~/other/.mcp.json", argv: ["profile", "attach", "/Users/me/other/.mcp.json"], destructive: false
        )]
        let group = try XCTUnwrap(DoctorAdvice.groups(rows).first)
        XCTAssertEqual(group.facts, [])
        XCTAssertEqual(group.rowText(rows[1]), "mcp-urlscan · tool urlscan · started by " + home("/Users/me/other/.mcp.json"))
        XCTAssertEqual(group.groupActions.map(\.title), ["Attach for Security-Ops/.mcp.json", "Attach for other/.mcp.json"])
        XCTAssertEqual(group.groupActions.map(\.planned), [
            .attach(config: "/Users/me/Security-Ops/.mcp.json"), .attach(config: "/Users/me/other/.mcp.json")
        ])
        var gone = try items("config_deleted")
        gone[1].configs = ["/Users/me/other/.mcp.json"]
        let deleted = try XCTUnwrap(DoctorAdvice.groups(gone).first)
        XCTAssertEqual(deleted.rowText(gone[1]), "mcp-okta · tool okta-mcp-server · started by " + home("/Users/me/other/.mcp.json")
            + " · recorded config " + home("/Users/me/Documents/ai_security_workspace/.mcp.json") + " is deleted")
    }

    func testButtonsPerKind() throws {
        for item in try items("profile_missing") {
            XCTAssertEqual(DoctorAdvice.actions(for: item), [], "the engine's note is the advice")
        }
        let set = try DoctorAdvice.actions(for: XCTUnwrap(items("pointer_missing").first))
        XCTAssertEqual(set.map(\.title), ["Set Value"])
        XCTAssertEqual(set[0].argv, [["vault", "set", "jitpass-playground-bak/API_KEY", "--stdin", "--yes"]])
        XCTAssertEqual(set[0].input, .secret(prompt: "The value for jitpass-playground-bak/API_KEY"))
        XCTAssertFalse(set[0].destructive)
        XCTAssertTrue(set[0].presence)

        for kind in ["config_deleted", "config_not_recorded"] {
            for item in try items(kind) {
                XCTAssertEqual(DoctorAdvice.actions(for: item), [], "attach is the group's button, not the row's")
            }
            let attach = try group(kind).groupActions
            XCTAssertEqual(attach.map(\.title), ["Attach 4"], "one config, one button, counting both groups' rows")
            XCTAssertEqual(attach[0].command, "jit profile attach ~/Security-Ops/.mcp.json")
            XCTAssertEqual(attach[0].argv, [["profile", "attach", "--yes", "/Users/me/Security-Ops/.mcp.json"]])
            XCTAssertEqual(attach[0].planned, .attach(config: "/Users/me/Security-Ops/.mcp.json"))
            XCTAssertFalse(attach[0].destructive)
            XCTAssertFalse(attach[0].presence)
        }

        let remove = try items("no_known_tool").map(DoctorAdvice.actions(for:))
        XCTAssertEqual(remove.map { $0.map(\.title) }, [["Remove Profile"], ["Remove Profile"]])
        let token = remove[1][0]
        XCTAssertEqual(token.command, "jit profile rm token")
        XCTAssertEqual(token.planned, .removeProfile(name: "token", manifest: "/Users/me/.jit/profiles/token.yaml"))
        XCTAssertEqual(token.argv, [["profile", "rm", "--yes", "token"]])
        XCTAssertTrue(token.destructive)
        XCTAssertTrue(token.presence, "the engine: Touch ID when secrets go")
    }

    /// The engine decides what is offered: a no-known-tool row whose fixes
    /// leave out `profile rm` gets no Remove Profile.
    func testNoRemoveWithoutTheEnginesFix() throws {
        var token = try XCTUnwrap(items("no_known_tool").last)
        token.fixes = []
        XCTAssertEqual(DoctorAdvice.actions(for: token), [])
        var unrecorded = try XCTUnwrap(items("config_not_recorded").first)
        unrecorded.fixes = [DoctorFix(command: "jit profile attach a b", argv: ["profile", "attach", "/a", "b"], destructive: false)]
        XCTAssertEqual(DoctorAdvice.groups([unrecorded]).first?.groupActions, [], "only exactly `profile attach <config>`")
    }
}
