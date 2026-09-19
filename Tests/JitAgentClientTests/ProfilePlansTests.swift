// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// `jit profile attach --dry-run` and `jit profile rm --dry-run` (jit 2.0),
/// and the one dialog the app words from each before it runs anything.
/// Fixtures are real output of jit 2.0.0, home renamed to /Users/me.
final class ProfilePlansTests: XCTestCase {
    private let home = "/Users/me"

    private let attachJSON = #"""
    {"config":"/Users/me/Security-Ops/.mcp.json","profiles":[{"name":"mcp-caido","status":"config_deleted",
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"adds":["/Users/me/Security-Ops/.mcp.json"]},
    {"name":"mcp-google-workspace-investigate","status":"config_deleted",
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"adds":["/Users/me/Security-Ops/.mcp.json"]},
    {"name":"mcp-jamf","status":"config_deleted","owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],
    "adds":["/Users/me/Security-Ops/.mcp.json"]},{"name":"mcp-okta","status":"config_deleted",
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"adds":["/Users/me/Security-Ops/.mcp.json"]},
    {"name":"mcp-okta-mcp-server","status":"config_deleted","owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],
    "adds":["/Users/me/Security-Ops/.mcp.json"]},{"name":"mcp-google-workspace","status":"no_config","owners":[],
    "adds":["/Users/me/Security-Ops/.mcp.json"]},{"name":"mcp-urlscan","status":"no_config","owners":[],
    "adds":["/Users/me/Security-Ops/.mcp.json"]}]}
    """#

    private let tokenJSON = #"""
    {"profile":"token","scope":"global","launchers":[],"delete_secrets":["token/JSON_WEB_TOKEN_JWT"],"keep_secrets":[],
    "missing_secrets":[],"coverage_complete":true,"refused":false}
    """#

    private let oktaJSON = #"""
    {"profile":"mcp-okta","scope":"global","launchers":[{"kind":"mcp","file":"/Users/me/Security-Ops/.mcp.json",
    "detail":"okta-mcp-server","profile":"mcp-okta","layer":1}],"delete_secrets":["mcp-okta/OKTA_CLIENT_ID","mcp-okta/OKTA_KEY_ID",
    "mcp-okta/OKTA_PRIVATE_KEY"],"keep_secrets":[],"missing_secrets":[],"coverage_complete":true,"refused":true}
    """#

    private let k8sJSON = #"""
    {"profile":"k8s-docker-desktop","scope":"global","launchers":[],"delete_secrets":[],"keep_secrets":[],
    "missing_secrets":["k8s-docker-desktop/CLIENT_CERTIFICATE_DATA","k8s-docker-desktop/CLIENT_KEY_DATA"],"coverage_complete":true,
    "refused":false}
    """#

    // MARK: - attach

    func testDecodesAttach() throws {
        let plan = try ProfileAttachPlan.parse(Data(attachJSON.utf8))
        XCTAssertEqual(plan.config, "/Users/me/Security-Ops/.mcp.json")
        XCTAssertEqual(plan.profiles.count, 7)
        XCTAssertEqual(plan.profiles.map(\.status).filter { $0 == "config_deleted" }.count, 5)
        XCTAssertEqual(plan.profiles.last, ProfileAttachCandidate(
            name: "mcp-urlscan", status: "no_config", owners: [], adds: ["/Users/me/Security-Ops/.mcp.json"]
        ))
        XCTAssertEqual(ProfileAttachPlan.arguments(for: plan.config), [
            "profile", "attach", "--dry-run", "--format", "json", "/Users/me/Security-Ops/.mcp.json"
        ])
    }

    /// A pre-release jit 2.0 said owner_gone, no_owner and owned_elsewhere:
    /// they read as the new statuses, so the dialog words them the same.
    func testOldStatusesDecodeAsTheNewOnes() throws {
        let old = #"""
        {"config":"/c","profiles":[{"name":"a","status":"owner_gone","owners":["/gone"],"adds":["/c"]},
        {"name":"b","status":"no_owner","owners":[],"adds":["/c"]},{"name":"q","status":"owned_elsewhere","owners":["/d"]}]}
        """#
        let plan = try ProfileAttachPlan.parse(Data(old.utf8))
        XCTAssertEqual(plan.profiles.map(\.status), ["config_deleted", "no_config", "recorded_elsewhere"])
        XCTAssertEqual(plan.profiles.first, ProfileAttachCandidate(name: "a", status: "config_deleted", owners: ["/gone"], adds: ["/c"]))
        let dialog = plan.confirmation(home: home) { _ in false }
        XCTAssertTrue(dialog.message.contains("• a · records a deleted config\n• b · records no config\n"), dialog.message)
    }

    func testAttachConfirmationListsEveryProfileAndRunsExactlyThose() throws {
        let dialog = try ProfileAttachPlan.parse(Data(attachJSON.utf8)).confirmation(home: home) { _ in false }
        XCTAssertEqual(dialog.title, "Record Security-Ops/.mcp.json on 7 profiles?")
        XCTAssertEqual(dialog.button, "Attach 7")
        XCTAssertFalse(dialog.destructive)
        XCTAssertFalse(dialog.breaks, "Return attaches: nothing is deleted")
        let names = [
            "mcp-caido", "mcp-google-workspace-investigate", "mcp-jamf", "mcp-okta", "mcp-okta-mcp-server",
            "mcp-google-workspace", "mcp-urlscan"
        ]
        XCTAssertEqual(dialog.arguments, ["profile", "attach", "--yes", "/Users/me/Security-Ops/.mcp.json"] + names)
        XCTAssertEqual(dialog.message, """
        ~/Security-Ops/.mcp.json uses these, but they don't record it:
        • mcp-caido · records a deleted config
        • mcp-google-workspace-investigate · records a deleted config
        • mcp-jamf · records a deleted config
        • mcp-okta · records a deleted config
        • mcp-okta-mcp-server · records a deleted config
        • mcp-google-workspace · records no config
        • mcp-urlscan · records no config

        Attaching records ~/Security-Ops/.mcp.json, so jit migrate remove ~/Security-Ops will then take them too.

        This runs:

        jit profile attach --yes ~/Security-Ops/.mcp.json
        + the 7 profiles listed above

        It changes which configs the profiles record: no secret is read or changed, and nothing asks again.
        """)
    }

    func testAttachOneProfile() {
        let plan = ProfileAttachPlan(config: "/Users/me/.claude.json", profiles: [ProfileAttachCandidate(name: "p", status: "no_config")])
        let dialog = plan.confirmation(home: home) { _ in false }
        XCTAssertEqual(dialog.title, "Record ~/.claude.json on p?")
        XCTAssertEqual(dialog.button, "Attach")
        XCTAssertTrue(dialog.message.hasPrefix("~/.claude.json uses this profile, which doesn't record it:\n• p · records no config\n\n"
                + "Attaching records ~/.claude.json.\n\n"), dialog.message)
        XCTAssertTrue(dialog.message.hasSuffix("It changes which configs the profile records: no secret is read or changed, "
                + "and nothing asks again."), dialog.message)
    }

    /// The migrate remove clause follows the engine's rule: a project
    /// directory, not home or an app's folder, and only for profiles that
    /// record no other live config.
    func testAttachMigrateRemoveClause() {
        let one = [ProfileAttachCandidate(name: "p", status: "no_config")]
        XCTAssertNil(ProfileAttachPlan(config: "/Users/me/.claude.json", profiles: one).migrateRemoveClause(home: home))
        XCTAssertNil(ProfileAttachPlan(config: "/Users/me/.cursor/mcp.json", profiles: one).migrateRemoveClause(home: home))
        XCTAssertNil(ProfileAttachPlan(config: "/Users/me/Library/App/mcp.json", profiles: one).migrateRemoveClause(home: home))
        XCTAssertEqual(
            ProfileAttachPlan(config: "/Users/me/proj/.mcp.json", profiles: one).migrateRemoveClause(home: home),
            "jit migrate remove ~/proj will then take it too"
        )
        let elsewhere = ProfileAttachCandidate(name: "q", status: "recorded_elsewhere", owners: ["/Users/me/b/.mcp.json"])
        XCTAssertNil(ProfileAttachPlan(config: "/Users/me/proj/.mcp.json", profiles: [elsewhere]).migrateRemoveClause(home: home))
        let mixed = ProfileAttachPlan(config: "/Users/me/proj/.mcp.json", profiles: one + [elsewhere])
        XCTAssertEqual(
            mixed.migrateRemoveClause(home: home), "jit migrate remove ~/proj will then take the 1 that record no other config too"
        )
        let dialog = mixed.confirmation(home: home) { $0 == "/Users/me/b/.mcp.json" }
        XCTAssertTrue(dialog.message.contains("• q · records ~/b/.mcp.json"), dialog.message)
        let gone = mixed.confirmation(home: home) { _ in false }
        XCTAssertTrue(gone.message.contains("• q · records another config"), gone.message)
    }

    func testNothingToAttach() throws {
        let dialog = try ProfileAttachPlan.parse(Data(#"{"config":"/Users/me/p/.mcp.json","profiles":[]}"#.utf8))
            .confirmation(home: home)
        XCTAssertEqual(dialog.title, "Nothing to attach")
        XCTAssertEqual(dialog.message, "Every profile ~/p/.mcp.json uses records it already.")
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
        No tool jit can see uses token. It can't see scripts or aliases: if one still runs it, that stops working.

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
        No tool jit can see uses k8s-docker-desktop. It can't see scripts or aliases: if one still runs it, that stops working.

        It deletes the profile; its 2 secrets are already gone:
        k8s-docker-desktop/CLIENT_CERTIFICATE_DATA
        k8s-docker-desktop/CLIENT_KEY_DATA

        This runs:

        jit profile rm --yes k8s-docker-desktop

        Nothing asks again, and no Touch ID: no secret is deleted.
        """)
    }

    /// A tool started using it between the doctor check and the click: jit
    /// would refuse, so the app offers nothing to run.
    func testRefusedNamesTheToolAndOffersNothing() throws {
        let dialog = try ProfileRmPlan.parse(Data(oktaJSON.utf8)).confirmation(home: home)
        XCTAssertEqual(dialog.title, "mcp-okta is in use")
        XCTAssertNil(dialog.button)
        XCTAssertEqual(dialog.arguments, [])
        XCTAssertEqual(dialog.message, """
        jit won't remove a profile a tool uses, so nothing was deleted.

        • tool okta-mcp-server uses it (~/Security-Ops/.mcp.json)

        Remove the okta-mcp-server entry from that file first.
        """)
    }

    func testKeptSecretsAndIncompleteCoverage() {
        let plan = ProfileRmPlan(
            profile: "dev", deleteSecrets: ["dev/A", "dev/B"], keepSecrets: ["shared/C"], missingSecrets: ["dev/D"],
            coverageComplete: false
        )
        let dialog = plan.confirmation(home: home)
        XCTAssertEqual(dialog.title, "jit can't see every tool that might use dev")
        XCTAssertEqual(dialog.button, "Remove Anyway")
        XCTAssertTrue(dialog.breaks)
        XCTAssertEqual(dialog.paths, ["dev/A", "dev/B"])
        XCTAssertTrue(dialog.message.hasPrefix("jit could not see all of your home folder"), dialog.message)
        XCTAssertTrue(dialog.message.contains("the 2 secrets nothing else uses, history and all:\ndev/A\ndev/B"), dialog.message)
        XCTAssertTrue(dialog.message.contains("Kept, because something else uses it:\nshared/C"), dialog.message)
        XCTAssertTrue(dialog.message.contains("Already gone: dev/D."), dialog.message)
        XCTAssertTrue(dialog.message.hasSuffix("Touch ID follows."), dialog.message)
    }

    /// A config jit could not read: it refuses too, so no button.
    func testCantTellRunsNothing() throws {
        let json = #"{"profile":"x","launchers":[],"refused":true,"coverage_complete":false,"error":"reading ~/.aws/config: denied"}"#
        let dialog = try ProfileRmPlan.parse(Data(json.utf8)).confirmation(home: home)
        XCTAssertEqual(dialog.title, "Can't tell whether x is in use")
        XCTAssertNil(dialog.button)
        XCTAssertTrue(dialog.message.contains("reading ~/.aws/config: denied"))
    }

    func testRefusalHintsPerToolKind() {
        let hint = { (launchers: [DoctorLauncher]) in ProfileRmPlan.refusalHint(launchers, home: self.home) }
        XCTAssertEqual(hint([DoctorLauncher(kind: "wrap", file: "/x", detail: "gh")]),
                       "jit wrap undo gh unwraps the tool and removes this profile with it.")
        XCTAssertEqual(hint([DoctorLauncher(kind: "mount", file: "/x", detail: "/Users/me/p/.env")]),
                       "jit migrate remove ~/p/.env restores the file and removes the profile with it.")
        XCTAssertEqual(hint([DoctorLauncher(kind: "aws", file: "/x", detail: "[profile dev]"), DoctorLauncher(kind: "mcp", file: "/y")]),
                       "Remove each of those first.")
    }

    /// Each refusal bullet names the tool, then where it is.
    func testToolLinePerKind() {
        let line = { (kind: String, file: String, detail: String) in
            ProfileRmPlan.toolLine(DoctorLauncher(kind: kind, file: file, detail: detail), home: self.home)
        }
        XCTAssertEqual(line("mcp", "/Users/me/Security-Ops/.mcp.json", "okta-mcp-server"),
                       "tool okta-mcp-server uses it (~/Security-Ops/.mcp.json)")
        XCTAssertEqual(line("aws", "/Users/me/.aws/config", "[profile dev]"), "tool aws uses it (~/.aws/config [profile dev])")
        XCTAssertEqual(line("kube", "/Users/me/.kube/config", "user dev"), "tool kubectl uses it (~/.kube/config user dev)")
        XCTAssertEqual(line("wrap", "/Users/me/.jit/wrap.json", "gh"), "wrapped tool gh uses it")
        XCTAssertEqual(line("shell_rc", "/Users/me/.zshrc", "line 12"), "~/.zshrc exports it (line 12)")
        XCTAssertEqual(line("helper", "/Users/me/bin/helper", "docker"), "~/bin/helper uses it")
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
        XCTAssertTrue(dialog.message.hasSuffix("That jit is older than 2.0, the first with jit profile. Update it."), dialog.message)
        let other = DeleteConfirmation.profileUnavailable("t", command: "jit profile attach", reason: "permission denied")
        XCTAssertFalse(other.message.contains("older"))
    }

    /// Attach and Remove Profile never fall through to the generic
    /// confirmation: the planned flow words them from the dry run.
    func testPlannedActionsAreMarked() {
        let item = DoctorItem(
            kind: "no_known_tool", scope: "global", profile: "token", variable: nil, path: nil, detail: "no known tool; 1 secret",
            action: nil, fixes: nil
        )
        XCTAssertEqual(DoctorAdvice.actions(for: item).map(\.planned), [.removeProfile(name: "token")])
    }
}
