// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// `jit profile adopt --dry-run` and `jit profile rm --dry-run` (jit 1.10),
/// and the one dialog the app words from each before it runs anything.
/// Fixtures are real output of jit main, home renamed to /Users/me.
final class ProfilePlansTests: XCTestCase {
    private let home = "/Users/me"

    private let adoptJSON = #"""
    {"config":"/Users/me/Security-Ops/.mcp.json","profiles":[{"name":"mcp-caido","status":"owner_gone",
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"adds":["/Users/me/Security-Ops/.mcp.json"]},
    {"name":"mcp-google-workspace-investigate","status":"owner_gone",
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"adds":["/Users/me/Security-Ops/.mcp.json"]},
    {"name":"mcp-jamf","status":"owner_gone","owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],
    "adds":["/Users/me/Security-Ops/.mcp.json"]},{"name":"mcp-okta","status":"owner_gone",
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"adds":["/Users/me/Security-Ops/.mcp.json"]},
    {"name":"mcp-okta-mcp-server","status":"owner_gone",
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"adds":["/Users/me/Security-Ops/.mcp.json"]},
    {"name":"mcp-google-workspace","status":"no_owner","owners":[],"adds":["/Users/me/Security-Ops/.mcp.json"]},
    {"name":"mcp-urlscan","status":"no_owner","owners":[],"adds":["/Users/me/Security-Ops/.mcp.json"]}]}
    """#

    private let tokenJSON = #"""
    {"profile":"token","scope":"global","launchers":[],"delete_secrets":["token/JSON_WEB_TOKEN_JWT"],"keep_secrets":[],
    "missing_secrets":[],"coverage_complete":true,"refused":false}
    """#

    private let oktaJSON = #"""
    {"profile":"mcp-okta","scope":"global","launchers":[{"kind":"mcp","file":"/Users/me/Security-Ops/.mcp.json",
    "detail":"okta-mcp-server","profile":"mcp-okta","layer":1}],"delete_secrets":["mcp-okta/OKTA_CLIENT_ID",
    "mcp-okta/OKTA_KEY_ID","mcp-okta/OKTA_PRIVATE_KEY"],"keep_secrets":[],"missing_secrets":[],"coverage_complete":true,
    "refused":true}
    """#

    private let k8sJSON = #"""
    {"profile":"k8s-docker-desktop","scope":"global","launchers":[],"delete_secrets":[],"keep_secrets":[],
    "missing_secrets":["k8s-docker-desktop/CLIENT_CERTIFICATE_DATA","k8s-docker-desktop/CLIENT_KEY_DATA"],
    "coverage_complete":true,"refused":false}
    """#

    // MARK: - adopt

    func testDecodesAdopt() throws {
        let plan = try ProfileAdoptPlan.parse(Data(adoptJSON.utf8))
        XCTAssertEqual(plan.config, "/Users/me/Security-Ops/.mcp.json")
        XCTAssertEqual(plan.profiles.count, 7)
        XCTAssertEqual(plan.profiles.map(\.status).filter { $0 == "owner_gone" }.count, 5)
        XCTAssertEqual(plan.profiles.last, ProfileAdoptCandidate(
            name: "mcp-urlscan", status: "no_owner", owners: [], adds: ["/Users/me/Security-Ops/.mcp.json"]
        ))
        XCTAssertEqual(ProfileAdoptPlan.arguments(for: plan.config), [
            "profile", "adopt", "--dry-run", "--format", "json", "/Users/me/Security-Ops/.mcp.json"
        ])
    }

    func testAdoptConfirmationListsEveryProfileAndRunsExactlyThose() throws {
        let dialog = try ProfileAdoptPlan.parse(Data(adoptJSON.utf8)).confirmation(home: home) { _ in false }
        XCTAssertEqual(dialog.title, "Adopt 7 profiles?")
        XCTAssertEqual(dialog.button, "Adopt 7")
        XCTAssertFalse(dialog.destructive)
        XCTAssertFalse(dialog.breaks, "Return adopts: nothing is deleted")
        let names = [
            "mcp-caido", "mcp-google-workspace-investigate", "mcp-jamf", "mcp-okta", "mcp-okta-mcp-server",
            "mcp-google-workspace", "mcp-urlscan"
        ]
        XCTAssertEqual(dialog.arguments, ["profile", "adopt", "--yes", "/Users/me/Security-Ops/.mcp.json"] + names)
        XCTAssertEqual(dialog.message, """
        ~/Security-Ops/.mcp.json launches these but doesn't own them:
        • mcp-caido · owner gone
        • mcp-google-workspace-investigate · owner gone
        • mcp-jamf · owner gone
        • mcp-okta · owner gone
        • mcp-okta-mcp-server · owner gone
        • mcp-google-workspace · no owner
        • mcp-urlscan · no owner

        Adopting records ~/Security-Ops/.mcp.json as their owner, so jit migrate remove ~/Security-Ops will then take them too.

        This runs:

        jit profile adopt --yes ~/Security-Ops/.mcp.json \(names.joined(separator: " "))

        It changes owner records only: no secret is read or changed, and nothing asks again.
        """)
    }

    /// The migrate remove clause follows the engine's rule: a project
    /// directory, not home or an app's folder, and only for profiles no
    /// other live config owns.
    func testAdoptMigrateRemoveClause() {
        let one = [ProfileAdoptCandidate(name: "p", status: "no_owner")]
        XCTAssertNil(ProfileAdoptPlan(config: "/Users/me/.claude.json", profiles: one).migrateRemoveClause(home: home))
        XCTAssertNil(ProfileAdoptPlan(config: "/Users/me/.cursor/mcp.json", profiles: one).migrateRemoveClause(home: home))
        XCTAssertNil(ProfileAdoptPlan(config: "/Users/me/Library/App/mcp.json", profiles: one).migrateRemoveClause(home: home))
        XCTAssertEqual(
            ProfileAdoptPlan(config: "/Users/me/proj/.mcp.json", profiles: one).migrateRemoveClause(home: home),
            "jit migrate remove ~/proj will then take it too"
        )
        let elsewhere = ProfileAdoptCandidate(name: "q", status: "owned_elsewhere", owners: ["/Users/me/b/.mcp.json"])
        XCTAssertNil(ProfileAdoptPlan(config: "/Users/me/proj/.mcp.json", profiles: [elsewhere]).migrateRemoveClause(home: home))
        let mixed = ProfileAdoptPlan(config: "/Users/me/proj/.mcp.json", profiles: one + [elsewhere])
        XCTAssertEqual(mixed.migrateRemoveClause(home: home), "jit migrate remove ~/proj will then take the 1 with no other owner too")
        let dialog = mixed.confirmation(home: home) { $0 == "/Users/me/b/.mcp.json" }
        XCTAssertTrue(dialog.message.contains("• q · owned by ~/b/.mcp.json"), dialog.message)
    }

    func testNothingToAdopt() throws {
        let dialog = try ProfileAdoptPlan.parse(Data(#"{"config":"/Users/me/p/.mcp.json","profiles":[]}"#.utf8))
            .confirmation(home: home)
        XCTAssertEqual(dialog.title, "Nothing to adopt")
        XCTAssertNil(dialog.button)
    }

    // MARK: - rm

    func testDecodesRm() throws {
        let token = try ProfileRmPlan.parse(Data(tokenJSON.utf8))
        XCTAssertEqual(token.profile, "token")
        XCTAssertEqual(token.deleteSecrets, ["token/JSON_WEB_TOKEN_JWT"])
        XCTAssertTrue(token.coverageComplete)
        XCTAssertFalse(token.refused)
        XCTAssertNil(token.error)
        let okta = try ProfileRmPlan.parse(Data(oktaJSON.utf8))
        XCTAssertTrue(okta.refused)
        XCTAssertEqual(okta.launchers.first?.detail, "okta-mcp-server")
        XCTAssertEqual(okta.launchers.first?.layer, 1)
        let k8s = try ProfileRmPlan.parse(Data(k8sJSON.utf8))
        XCTAssertEqual(k8s.missingSecrets.count, 2)
        let bare = try ProfileRmPlan.parse(Data(#"{"profile":"x"}"#.utf8))
        XCTAssertFalse(bare.coverageComplete, "absent coverage is not complete coverage")
        XCTAssertEqual(ProfileRmPlan.arguments(for: "token"), ["profile", "rm", "--dry-run", "--format", "json", "token"])
    }

    func testRemoveTokenDeletesItsSecretAfterTouchID() throws {
        let dialog = try ProfileRmPlan.parse(Data(tokenJSON.utf8)).confirmation(home: home)
        XCTAssertEqual(dialog.title, "Remove profile token?")
        XCTAssertEqual(dialog.button, "Remove Profile")
        XCTAssertTrue(dialog.breaks, "Cancel is the default, Escape cancels")
        XCTAssertTrue(dialog.destructive)
        XCTAssertEqual(dialog.arguments, ["profile", "rm", "--yes", "token"])
        XCTAssertEqual(dialog.message, """
        Nothing jit can see launches token. It can't see scripts or aliases: if one still runs it, that stops working.

        It deletes the profile and the secret nothing else uses, history and all:
        token/JSON_WEB_TOKEN_JWT

        This runs:

        jit profile rm --yes token

        Nothing asks again. Touch ID follows.
        """)
    }

    func testRemoveProfileWhoseSecretsAreGoneAsksNoTouchID() throws {
        let dialog = try ProfileRmPlan.parse(Data(k8sJSON.utf8)).confirmation(home: home)
        XCTAssertEqual(dialog.title, "Remove profile k8s-docker-desktop?")
        XCTAssertEqual(dialog.button, "Remove Profile")
        XCTAssertEqual(dialog.message, """
        Nothing jit can see launches k8s-docker-desktop. It can't see scripts or aliases: if one still runs it, that stops working.

        It deletes the profile; its 2 secrets are already gone:
        k8s-docker-desktop/CLIENT_CERTIFICATE_DATA
        k8s-docker-desktop/CLIENT_KEY_DATA

        This runs:

        jit profile rm --yes k8s-docker-desktop

        Nothing asks again, and no Touch ID: no secret is deleted.
        """)
    }

    /// Something launched it between the doctor check and the click: jit
    /// would refuse, so the app offers nothing to run.
    func testRefusedNamesTheLauncherAndOffersNothing() throws {
        let dialog = try ProfileRmPlan.parse(Data(oktaJSON.utf8)).confirmation(home: home)
        XCTAssertEqual(dialog.title, "mcp-okta is in use")
        XCTAssertNil(dialog.button)
        XCTAssertEqual(dialog.arguments, [])
        XCTAssertEqual(dialog.message, """
        jit won't remove a profile something launches, so nothing was deleted.

        • ~/Security-Ops/.mcp.json launches it (okta-mcp-server)

        Remove the okta-mcp-server entry from that file first.
        """)
    }

    func testKeptSecretsAndIncompleteCoverage() {
        let plan = ProfileRmPlan(
            profile: "dev", deleteSecrets: ["dev/A", "dev/B"], keepSecrets: ["shared/C"], missingSecrets: ["dev/D"],
            coverageComplete: false
        )
        let dialog = plan.confirmation(home: home)
        XCTAssertEqual(dialog.title, "jit can't see everything that might launch dev")
        XCTAssertEqual(dialog.button, "Remove Anyway")
        XCTAssertTrue(dialog.breaks)
        XCTAssertEqual(dialog.paths, ["dev/A", "dev/B"])
        XCTAssertTrue(dialog.message.hasPrefix("jit could not see all of your home folder"), dialog.message)
        XCTAssertTrue(dialog.message.contains("the 2 secrets nothing else uses, history and all:\ndev/A\ndev/B"), dialog.message)
        XCTAssertTrue(dialog.message.contains("Kept, because something else uses it:\nshared/C"), dialog.message)
        XCTAssertTrue(dialog.message.contains("Already gone: dev/D."), dialog.message)
        XCTAssertTrue(dialog.message.hasSuffix("Touch ID follows."), dialog.message)
    }

    /// A launcher source jit could not read: it refuses too, so no button.
    func testCantTellRunsNothing() throws {
        let json = #"{"profile":"x","launchers":[],"refused":true,"coverage_complete":false,"error":"reading ~/.aws/config: denied"}"#
        let dialog = try ProfileRmPlan.parse(Data(json.utf8)).confirmation(home: home)
        XCTAssertEqual(dialog.title, "Can't tell whether x is in use")
        XCTAssertNil(dialog.button)
        XCTAssertTrue(dialog.message.contains("reading ~/.aws/config: denied"))
    }

    func testRefusalHintsPerLauncherKind() {
        let hint = { (launchers: [DoctorLauncher]) in ProfileRmPlan.refusalHint(launchers, home: self.home) }
        XCTAssertEqual(hint([DoctorLauncher(kind: "wrap", file: "/x", detail: "gh")]),
                       "jit wrap undo gh unwraps the tool and removes this profile with it.")
        XCTAssertEqual(hint([DoctorLauncher(kind: "mount", file: "/x", detail: "/Users/me/p/.env")]),
                       "jit migrate remove ~/p/.env restores the file and removes the profile with it.")
        XCTAssertEqual(hint([DoctorLauncher(kind: "aws", file: "/x", detail: "[profile dev]"), DoctorLauncher(kind: "mcp", file: "/y")]),
                       "Remove each of those first.")
    }

    // MARK: - older jit

    /// jit 1.9 has no `jit profile`: its dry run fails with "unknown flag",
    /// and the app runs nothing.
    func testOlderJitFailsClosed() {
        let dialog = DeleteConfirmation.profileUnavailable(
            "Can't check what removing token deletes", command: "jit profile rm", reason: "unknown flag: --dry-run"
        )
        XCTAssertNil(dialog.button)
        XCTAssertEqual(dialog.arguments, [])
        XCTAssertTrue(dialog.message.hasPrefix("Nothing was changed."), dialog.message)
        XCTAssertTrue(dialog.message.hasSuffix("That jit is older than 1.10, the first with jit profile. Update it."), dialog.message)
        let other = DeleteConfirmation.profileUnavailable("t", command: "jit profile adopt", reason: "permission denied")
        XCTAssertFalse(other.message.contains("older"))
    }

    /// Adopt and Remove Profile never fall through to the generic
    /// confirmation: the planned flow words them from the dry run.
    func testPlannedActionsAreMarked() {
        let item = DoctorItem(
            kind: "unlaunched", scope: "global", profile: "token", variable: nil, path: nil, detail: "no known launcher; 1 secret",
            action: nil, fixes: nil
        )
        XCTAssertEqual(DoctorAdvice.actions(for: item).map(\.planned), [.removeProfile(name: "token")])
    }
}
