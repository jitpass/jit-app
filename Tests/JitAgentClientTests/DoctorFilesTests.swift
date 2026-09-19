// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// What the Doctor window says once rather than per row, how it counts an
/// Adopt, how a dialog shows a long command, and which file a row names.
final class DoctorFilesTests: XCTestCase {
    private func broken(_ kind: String, _ profile: String, action: String) -> DoctorItem {
        DoctorItem(
            kind: "launcher_broken", profile: profile, action: action, file: "/Users/me/.aws/config",
            launchers: [DoctorLauncher(kind: kind, file: "/Users/me/.aws/config", detail: "[profile \(profile)]", profile: profile)]
        )
    }

    private func aws(_ profile: String) -> DoctorItem {
        broken(
            "aws",
            profile,
            action: "no such jit profile, so aws --profile \(profile) fails; mint it again, or delete that [profile] block"
        )
    }

    // MARK: - broken launchers

    /// jit's own plural for several AWS sections, said once below them.
    func testBrokenLauncherAdviceOncePerKindPlural() throws {
        let group = try XCTUnwrap(DoctorAdvice.groups([aws("dev"), aws("admin")]).first)
        XCTAssertEqual(group.runs.count, 1)
        XCTAssertEqual(group.runs[0].items.map(\.profile), ["dev", "admin"])
        XCTAssertEqual(group.runs[0].note, "Mint them again, or delete those [profile] blocks")
    }

    func testBrokenLauncherAdviceSingular() throws {
        let group = try XCTUnwrap(DoctorAdvice.groups([aws("dev")]).first)
        XCTAssertEqual(group.runs.map(\.note), ["Mint it again, or delete that [profile] block"])
    }

    /// Runs by launcher kind in first-seen order; a kind jit words the same
    /// for many keeps its sentence; one the app doesn't know shows the
    /// first finding's action once.
    func testBrokenLauncherRunsPerKind() throws {
        let mcp = { (name: String) in
            self.broken("mcp", name, action: "no such jit profile, so that MCP server fails to start; "
                + "undo that migration, or drop that jit run layer")
        }
        let odd = { (name: String) in self.broken("teleport", name, action: "no such jit profile, so it fails") }
        let group = try XCTUnwrap(DoctorAdvice.groups([mcp("a"), aws("dev"), mcp("b"), aws("admin"), odd("x"), odd("y")]).first)
        XCTAssertEqual(group.runs.map { $0.items.compactMap(\.profile) }, [["a", "b"], ["dev", "admin"], ["x", "y"]])
        XCTAssertEqual(group.runs.map(\.note), [
            "Undo that migration, or drop that jit run layer",
            "Mint them again, or delete those [profile] blocks",
            "No such jit profile, so it fails"
        ])
    }

    func testOtherKindsAreOneRunWithoutNote() throws {
        let item = DoctorItem(kind: "mount", path: "/Users/me/p/.env", action: "`jit unmount ~/p/.env`")
        let group = try XCTUnwrap(DoctorAdvice.groups([item, item]).first)
        XCTAssertEqual(group.runs.map(\.items.count), [2])
        XCTAssertEqual(group.runs.map(\.note), [nil])
    }

    // MARK: - Adopt

    private func owner(_ kind: String, _ profile: String, config: String) -> DoctorItem {
        DoctorItem(
            kind: kind, scope: "global", profile: profile, path: "/Users/me/.jit/profiles/\(profile).yaml",
            fixes: [DoctorFix(command: "jit profile adopt \(config)", argv: ["profile", "adopt", config], destructive: false)],
            config: config, configs: [config], owners: kind == "owner_gone" ? ["/Users/me/gone/.mcp.json"] : nil
        )
    }

    /// Adopting a config takes its profiles in both groups, so each Adopt
    /// counts them all and reads the same wherever it shows; named by
    /// config once the report has more than one.
    func testAdoptCountsAcrossBothGroupsPerConfig() {
        let ops = "/Users/me/Security-Ops/.mcp.json"
        let other = NSHomeDirectory() + "/.claude.json"
        let items = [
            owner("owner_gone", "a", config: ops), owner("owner_gone", "b", config: ops),
            owner("no_owner", "c", config: ops), owner("no_owner", "d", config: other)
        ]
        let groups = DoctorAdvice.groups(items, among: items)
        XCTAssertEqual(groups.map(\.kind), ["owner_gone", "no_owner"])
        XCTAssertEqual(groups[0].groupActions.map(\.title), ["Adopt 3 for Security-Ops/.mcp.json"])
        XCTAssertEqual(groups[1].groupActions.map(\.title), [
            "Adopt 3 for Security-Ops/.mcp.json", "Adopt for ~/.claude.json"
        ])
        XCTAssertEqual(groups[1].groupActions.map(\.planned), [.adopt(config: ops), .adopt(config: other)])
        XCTAssertEqual(groups[1].groupActions[0].argv, [["profile", "adopt", "--yes", ops]], "the dry run decides the names")
    }

    func testAdoptOneConfigIsJustTheCount() throws {
        let ops = "/Users/me/Security-Ops/.mcp.json"
        let items = [owner("owner_gone", "a", config: ops), owner("no_owner", "b", config: ops), owner("no_owner", "c", config: ops)]
        let report = try JSONDecoder().decode(DoctorReport.self, from: JSONEncoder().encode(Wrapper(warnings: items)))
        XCTAssertEqual(report.warningGroups.map { $0.groupActions.map(\.title) }, [["Adopt 3"], ["Adopt 3"]])
        let alone = DoctorAdvice.groups([owner("no_owner", "z", config: ops)])
        XCTAssertEqual(alone.first?.groupActions.map(\.title), ["Adopt"], "one profile: the dialog's own word")
    }

    func testConfigShortName() {
        XCTAssertEqual(DoctorAdvice.configShortName("/Users/me/Security-Ops/.mcp.json"), "Security-Ops/.mcp.json")
        XCTAssertEqual(DoctorAdvice.configShortName("/etc/jit/mcp.json"), "jit/mcp.json")
        XCTAssertEqual(DoctorAdvice.configShortName("/mcp.json"), "/mcp.json")
    }

    // MARK: - This runs:

    func testCommandTextMovesManyNamesOffTheLine() {
        let fixed = ["profile", "adopt", "--yes", "~/p/.mcp.json"]
        let noun = (one: "profile", many: "profiles")
        let four = ["mcp-a-b", "mcp-c-d", "mcp-e", "mcp-f"]
        XCTAssertEqual(
            CommandText.shown(fixed, names: four, noun: noun, listedAbove: true),
            "jit profile adopt --yes ~/p/.mcp.json\n+ the 4 profiles listed above"
        )
        XCTAssertEqual(
            CommandText.shown(fixed, names: Array(four.prefix(3)), noun: noun, listedAbove: true),
            "jit profile adopt --yes ~/p/.mcp.json mcp-a-b mcp-c-d mcp-e", "a few stay on the line"
        )
        XCTAssertEqual(
            CommandText.shown(fixed, names: ["mcp-a-b"], noun: noun, listedAbove: true, always: true),
            "jit profile adopt --yes ~/p/.mcp.json\n+ the profile listed above"
        )
        XCTAssertEqual(
            CommandText.shown(
                ["vault", "rm", "--yes"],
                names: ["a/1", "a/2", "a/3", "a/4"],
                noun: ("secret", "secrets"),
                listedAbove: false
            ),
            "jit vault rm --yes\n+ these 4 secrets:\na/1\na/2\na/3\na/4"
        )
    }

    /// Only the text changes: the delete still runs every path.
    func testVaultRmShowsManyPathsOnePerLineAndRunsThemAll() throws {
        let paths = ["mcp-okta/OKTA_CLIENT_ID", "mcp-okta/OKTA_KEY_ID", "mcp-okta/OKTA_PRIVATE_KEY", "mcp-okta/OKTA_ORG"]
        let dialog = VaultRmPlan(paths: paths).confirmation(home: "/Users/me")
        XCTAssertEqual(dialog.arguments, ["vault", "rm", "--yes"] + paths)
        XCTAssertTrue(dialog.message.hasPrefix("This runs:\n\njit vault rm --yes\n+ these 4 secrets:\n"
                + paths.joined(separator: "\n") + "\n\n"), dialog.message)
        let few = try VaultRmPlan.parse(Data(#"{"paths":["gh/TOKEN","gh/OTHER"]}"#.utf8)).confirmation(home: "/Users/me")
        XCTAssertTrue(few.message.hasPrefix("This runs:\n\njit vault rm --yes gh/TOKEN gh/OTHER\n\n"), few.message)
    }

    // MARK: - files

    /// Which field a row's Show in Finder takes, per kind.
    func testFilePathPerKind() {
        var launcher = aws("dev")
        XCTAssertEqual(DoctorAdvice.filePath(launcher), "/Users/me/.aws/config")
        launcher.file = "/Users/me/.aws/other"
        XCTAssertEqual(DoctorAdvice.filePath(launcher), "/Users/me/.aws/other", "the finding's file wins")
        launcher.file = nil
        launcher.launchers?[0].file = "/Users/me/.kube/config"
        XCTAssertEqual(DoctorAdvice.filePath(launcher), "/Users/me/.kube/config", "then its launcher's")

        let pointer = DoctorItem(kind: "pointer_missing", path: "bak/API_KEY", file: "/Users/me/p/.env.bak")
        XCTAssertEqual(DoctorAdvice.filePath(pointer), "/Users/me/p/.env.bak", "the pointer file, never the secret's vault path")
        XCTAssertNil(DoctorAdvice.filePath(DoctorItem(kind: "pointer_missing", path: "bak/API_KEY")))

        let manifest = "/Users/me/.jit/profiles/token.yaml"
        for kind in ["owner_gone", "no_owner", "unlaunched"] {
            let item = DoctorItem(kind: kind, profile: "token", path: manifest, config: "/Users/me/p/.mcp.json")
            XCTAssertEqual(DoctorAdvice.filePath(item), manifest, kind)
        }
        for kind in ["mcp", "mcp_nested", "mount", "mount_stale", "jit_path", "install", "origin_gone"] {
            XCTAssertEqual(DoctorAdvice.filePath(DoctorItem(kind: kind, path: "/Users/me/p/x")), "/Users/me/p/x", kind)
        }
        for kind in ["missing", "corrupt", "orphan", "1password_link"] {
            XCTAssertNil(DoctorAdvice.filePath(DoctorItem(kind: kind, path: "gh/TOKEN")), "\(kind): a vault path is no file")
        }
        XCTAssertNil(DoctorAdvice.filePath(DoctorItem(kind: "mcp", path: "")))
    }

    func testProfileManifest() {
        XCTAssertEqual(ProfileFiles.directory(home: "/Users/me"), "/Users/me/.jit/profiles")
        XCTAssertEqual(ProfileFiles.manifest("token", home: "/Users/me"), "/Users/me/.jit/profiles/token.yaml")
        XCTAssertEqual(ProfileFiles.manifest("token", reported: "", home: "/Users/me"), "/Users/me/.jit/profiles/token.yaml")
        XCTAssertEqual(
            ProfileFiles.manifest("token", reported: "/Users/me/elsewhere/token.yaml", home: "/Users/me"),
            "/Users/me/elsewhere/token.yaml", "the engine's path wins"
        )
    }
}

/// A report around some warnings, for decoding through `DoctorReport`.
private struct Wrapper: Encodable {
    var ok = false
    var schemaVersion = 2
    var problems: [DoctorItem] = []
    var warnings: [DoctorItem]

    enum CodingKeys: String, CodingKey {
        case ok, problems, warnings
        case schemaVersion = "schema_version"
    }
}
