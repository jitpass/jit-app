// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// Doctor's ownership kinds (jit 1.10): what the window titles them, what
/// each row says, and which buttons they get. Broken launchers get none,
/// a missing pointer Set Value, ownerless profiles one Adopt per config on
/// the group, an unlaunched profile Remove Profile.
final class DoctorOwnershipTests: XCTestCase {
    /// Trimmed from a real `jit doctor --format json` of jit main (to be
    /// 1.10), home renamed: two findings of each ownership kind.
    private let json = #"""
    {"schema_version":2,"tool":{"version":"v1.9.1"},"ok":false,"problems":[{"kind":"launcher_broken",
    "profile":"aws-dev","detail":"~/.aws/config [profile dev] names profile aws-dev, which no jit store holds",
    "action":"no such jit profile, so aws --profile dev fails; mint it again, or delete that [profile] block",
    "file":"/Users/me/.aws/config","launchers":[{"kind":"aws","file":"/Users/me/.aws/config","detail":"[profile dev]",
    "profile":"aws-dev"}]},{"kind":"launcher_broken","profile":"aws-admin",
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
    "warnings":[{"kind":"owner_gone","profile":"mcp-caido","scope":"global",
    "path":"/Users/me/.jit/profiles/mcp-caido.yaml",
    "detail":"made by ~/Documents/ai_security_workspace/.mcp.json, now gone; launched by ~/Security-Ops/.mcp.json",
    "action":"`jit profile adopt ~/Security-Ops/.mcp.json`",
    "fixes":[{"command":"jit profile adopt ~/Security-Ops/.mcp.json","argv":["profile","adopt",
    "/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],
    "config":"/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"launchers":[{"kind":"mcp",
    "file":"/Users/me/Security-Ops/.mcp.json","detail":"caido","profile":"mcp-caido"},{"kind":"mcp",
    "file":"/Users/me/Security-Ops/.mcp.json","detail":"caido","profile":"mcp-caido","layer":1}]},{"kind":"owner_gone",
    "profile":"mcp-okta","scope":"global","path":"/Users/me/.jit/profiles/mcp-okta.yaml",
    "detail":"made by ~/Documents/ai_security_workspace/.mcp.json, now gone; launched by ~/Security-Ops/.mcp.json",
    "action":"`jit profile adopt ~/Security-Ops/.mcp.json`",
    "fixes":[{"command":"jit profile adopt ~/Security-Ops/.mcp.json","argv":["profile","adopt",
    "/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],
    "config":"/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"launchers":[{"kind":"mcp",
    "file":"/Users/me/Security-Ops/.mcp.json","detail":"okta-mcp-server","profile":"mcp-okta","layer":1}]},
    {"kind":"no_owner","profile":"mcp-google-workspace","scope":"global",
    "path":"/Users/me/.jit/profiles/mcp-google-workspace.yaml",
    "detail":"no owner recorded; launched by ~/Security-Ops/.mcp.json",
    "action":"`jit profile adopt ~/Security-Ops/.mcp.json`",
    "fixes":[{"command":"jit profile adopt ~/Security-Ops/.mcp.json","argv":["profile","adopt",
    "/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],
    "config":"/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "launchers":[{"kind":"mcp","file":"/Users/me/Security-Ops/.mcp.json","detail":"google-workspace-investigate",
    "profile":"mcp-google-workspace","layer":1}]},{"kind":"no_owner","profile":"mcp-urlscan","scope":"global",
    "path":"/Users/me/.jit/profiles/mcp-urlscan.yaml",
    "detail":"no owner recorded; launched by ~/Security-Ops/.mcp.json",
    "action":"`jit profile adopt ~/Security-Ops/.mcp.json`",
    "fixes":[{"command":"jit profile adopt ~/Security-Ops/.mcp.json","argv":["profile","adopt",
    "/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],
    "config":"/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "launchers":[{"kind":"mcp","file":"/Users/me/Security-Ops/.mcp.json","detail":"urlscan","profile":"mcp-urlscan"}]},
    {"kind":"unlaunched","profile":"k8s-docker-desktop","scope":"global",
    "path":"/Users/me/.jit/profiles/k8s-docker-desktop.yaml","detail":"no known launcher; 2 secrets, both missing",
    "action":"`jit profile rm k8s-docker-desktop` if you no longer use it",
    "fixes":[{"command":"jit profile rm k8s-docker-desktop","argv":["profile","rm","k8s-docker-desktop"],
    "destructive":true,"presence":true}],"secrets":2,"secrets_missing":2},{"kind":"unlaunched","profile":"token",
    "scope":"global","path":"/Users/me/.jit/profiles/token.yaml","detail":"no known launcher; 1 secret",
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
        XCTAssertEqual(r.problems.map(\.kind), ["launcher_broken", "launcher_broken", "pointer_missing", "pointer_missing"])
        let broken = r.problems[0]
        XCTAssertEqual(broken.file, "/Users/me/.aws/config")
        XCTAssertEqual(
            broken.launchers,
            [DoctorLauncher(kind: "aws", file: "/Users/me/.aws/config", detail: "[profile dev]", profile: "aws-dev")]
        )
        XCTAssertEqual(broken.fixes, [], "a hand edit: the engine offers no command")
        let caido = try XCTUnwrap(items("owner_gone").first)
        XCTAssertEqual(caido.config, "/Users/me/Security-Ops/.mcp.json")
        XCTAssertEqual(caido.configs, ["/Users/me/Security-Ops/.mcp.json"])
        XCTAssertEqual(caido.owners, ["/Users/me/Documents/ai_security_workspace/.mcp.json"])
        XCTAssertEqual(caido.launchers?.map(\.layer), [nil, 1])
        let unlaunched = try items("unlaunched")
        XCTAssertEqual(unlaunched.map(\.secrets), [2, 1])
        XCTAssertEqual(unlaunched.map(\.secretsMissing), [2, nil])
        XCTAssertEqual(unlaunched.map(\.origin), [nil, "/Users/me/token.txt"])
        XCTAssertEqual(Set((r.problems + r.warnings).map(\.id)).count, r.problems.count + r.warnings.count)
    }

    func testTitlesAndNotes() throws {
        let titles = try ["launcher_broken", "pointer_missing", "owner_gone", "no_owner", "unlaunched"].map { try group($0).title }
        XCTAssertEqual(titles, [
            "Broken launchers", "Missing pointed-to secrets", "Profiles whose owner is gone", "Profiles with no owner", "No known launcher"
        ])
        XCTAssertTrue(try group("unlaunched").note?.contains("can't see scripts or aliases") ?? false)
        XCTAssertTrue(try group("launcher_broken").note?.contains("doesn't exist") ?? false)
        let gone = try XCTUnwrap(group("owner_gone").note)
        XCTAssertTrue(gone.hasSuffix(
            "Made by \(home("/Users/me/Documents/ai_security_workspace/.mcp.json")), now gone. "
                + "Launched by \(home("/Users/me/Security-Ops/.mcp.json"))."
        ), gone)
        XCTAssertTrue(try group("no_owner").note?.hasSuffix("Launched by \(home("/Users/me/Security-Ops/.mcp.json")).") ?? false)
    }

    func testRowText() throws {
        let broken = try group("launcher_broken")
        XCTAssertEqual(broken.items.map(broken.rowText), [
            home("/Users/me/.aws/config") + " [profile dev] names aws-dev",
            home("/Users/me/.aws/config") + " [profile admin] names aws-admin"
        ])
        XCTAssertEqual(DoctorAdvice.rowNote(broken.items[0]), "Mint it again, or delete that [profile] block")
        let pointers = try group("pointer_missing")
        XCTAssertEqual(pointers.rowText(pointers.items[1]), home("/Users/me/.clisso.yaml") + " · wrap-clisso/acme-client-secret")
        XCTAssertTrue(DoctorAdvice.rowIsPath(pointers.items[1]))
        XCTAssertNil(DoctorAdvice.rowNote(pointers.items[1]))
        let gone = try group("owner_gone")
        XCTAssertEqual(gone.items.map(gone.rowText), ["mcp-caido", "mcp-okta"], "the shared facts are on the note")
        let unlaunched = try group("unlaunched")
        XCTAssertEqual(unlaunched.items.map(unlaunched.rowText), [
            "k8s-docker-desktop · 2 secrets, both missing", "token · 1 secret · made from \(home("/Users/me/token.txt")), now gone"
        ])
    }

    /// Rows whose configs differ each say their own; the note says nothing
    /// it could get wrong for some of them.
    func testOwnerRowsThatDifferNameTheirConfigs() throws {
        var rows = try items("no_owner")
        rows[1].configs = ["/Users/me/other/.mcp.json"]
        rows[1].config = "/Users/me/other/.mcp.json"
        rows[1].fixes = [DoctorFix(
            command: "jit profile adopt ~/other/.mcp.json", argv: ["profile", "adopt", "/Users/me/other/.mcp.json"], destructive: false
        )]
        let group = try XCTUnwrap(DoctorAdvice.groups(rows).first)
        XCTAssertFalse(group.note?.contains("Launched by") ?? false)
        XCTAssertEqual(group.rowText(rows[1]), "mcp-urlscan · launched by " + home("/Users/me/other/.mcp.json"))
        XCTAssertEqual(group.groupActions.map(\.title), [
            "Adopt for " + DoctorAdvice.ellipsis(home("/Users/me/Security-Ops/.mcp.json"), 40),
            "Adopt for " + DoctorAdvice.ellipsis(home("/Users/me/other/.mcp.json"), 40)
        ])
        XCTAssertEqual(group.groupActions.map(\.planned), [
            .adopt(config: "/Users/me/Security-Ops/.mcp.json"), .adopt(config: "/Users/me/other/.mcp.json")
        ])
    }

    func testButtonsPerKind() throws {
        for item in try items("launcher_broken") {
            XCTAssertEqual(DoctorAdvice.actions(for: item), [], "the engine's note is the advice")
        }
        let set = try DoctorAdvice.actions(for: XCTUnwrap(items("pointer_missing").first))
        XCTAssertEqual(set.map(\.title), ["Set Value"])
        XCTAssertEqual(set[0].argv, [["vault", "set", "jitpass-playground-bak/API_KEY", "--stdin", "--yes"]])
        XCTAssertEqual(set[0].input, .secret(prompt: "The value for jitpass-playground-bak/API_KEY"))
        XCTAssertFalse(set[0].destructive)
        XCTAssertTrue(set[0].presence)

        for kind in ["owner_gone", "no_owner"] {
            for item in try items(kind) {
                XCTAssertEqual(DoctorAdvice.actions(for: item), [], "adopt is the group's button, not the row's")
            }
            let adopt = try group(kind).groupActions
            XCTAssertEqual(adopt.map(\.title), ["Adopt"], "one config, one button")
            XCTAssertEqual(adopt[0].command, "jit profile adopt ~/Security-Ops/.mcp.json")
            XCTAssertEqual(adopt[0].planned, .adopt(config: "/Users/me/Security-Ops/.mcp.json"))
            XCTAssertFalse(adopt[0].destructive)
            XCTAssertFalse(adopt[0].presence)
        }

        let remove = try items("unlaunched").map(DoctorAdvice.actions(for:))
        XCTAssertEqual(remove.map { $0.map(\.title) }, [["Remove Profile"], ["Remove Profile"]])
        let token = remove[1][0]
        XCTAssertEqual(token.command, "jit profile rm token")
        XCTAssertEqual(token.planned, .removeProfile(name: "token"))
        XCTAssertEqual(token.argv, [["profile", "rm", "--yes", "token"]])
        XCTAssertTrue(token.destructive)
        XCTAssertTrue(token.presence, "the engine: Touch ID when secrets go")
    }

    /// The engine decides what is offered: an unlaunched row whose fixes
    /// leave out `profile rm` gets no Remove Profile.
    func testNoRemoveWithoutTheEnginesFix() throws {
        var token = try XCTUnwrap(items("unlaunched").last)
        token.fixes = []
        XCTAssertEqual(DoctorAdvice.actions(for: token), [])
        var owner = try XCTUnwrap(items("no_owner").first)
        owner.fixes = [DoctorFix(command: "jit profile adopt a b", argv: ["profile", "adopt", "/a", "b"], destructive: false)]
        XCTAssertEqual(DoctorAdvice.groups([owner]).first?.groupActions, [], "only exactly `profile adopt <config>`")
    }
}
