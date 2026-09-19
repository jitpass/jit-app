// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// `jit vault rm --dry-run --format json`, and the one dialog the app
/// words from it before any delete. The incident this guards against: the
/// app ran `vault rm --yes` on secrets two live MCP profiles still used.
final class VaultRmPlanTests: XCTestCase {
    private let home = "/Users/me"

    /// The shape jit 1.9.0 prints for a secret an MCP profile uses.
    private let inUseJSON = #"""
    {"paths":["mcp-okta/TOKEN"],
     "in_use":[{"path":"mcp-okta/TOKEN","profile":"mcp-okta","scope":"global",
                "launched_by":["/Users/me/Security-Ops/.mcp.json"]}],
     "refused":true}
    """#

    func testDecodesInUse() throws {
        let plan = try VaultRmPlan.parse(Data(inUseJSON.utf8))
        XCTAssertEqual(plan.paths, ["mcp-okta/TOKEN"])
        XCTAssertTrue(plan.refused)
        XCTAssertNil(plan.error)
        XCTAssertFalse(plan.isClean)
        XCTAssertEqual(plan.inUse.first?.launchedBy, ["/Users/me/Security-Ops/.mcp.json"])
        XCTAssertEqual(plan.users.map(\.profile), ["mcp-okta"])
    }

    func testDecodesCleanErrorAndUnknownFields() throws {
        let cleanJSON = #"{"paths":["a/B"],"missing":["x/Y"],"refused":false,"schema":9,"new":{"k":1}}"#
        let clean = try VaultRmPlan.parse(Data(cleanJSON.utf8))
        XCTAssertTrue(clean.isClean)
        XCTAssertEqual(clean.missing, ["x/Y"])
        let failedJSON = #"{"paths":["a/B"],"refused":true,"error":"reading ~/p/.jit/profiles/x.json: permission denied"}"#
        let failed = try VaultRmPlan.parse(Data(failedJSON.utf8))
        XCTAssertFalse(failed.isClean, "can't tell is never unused")
        XCTAssertEqual(failed.error, "reading ~/p/.jit/profiles/x.json: permission denied")
        let pointerJSON = #"{"paths":["a/B"],"in_use":[{"path":"a/B","pointer_file":"/Users/me/.clisso.yaml","why":"new"}],"refused":true}"#
        let pointer = try VaultRmPlan.parse(Data(pointerJSON.utf8))
        XCTAssertEqual(pointer.users.first?.pointerFile, "/Users/me/.clisso.yaml")
        XCTAssertNil(pointer.users.first?.profile)
    }

    /// A refused plan with nothing named is still not clean: the app never
    /// runs the plain delete jit says it would refuse.
    func testRefusedWithoutReasonIsNotClean() throws {
        let plan = try VaultRmPlan.parse(Data(#"{"paths":["a/B"],"refused":true}"#.utf8))
        let dialog = plan.confirmation(home: home)
        XCTAssertTrue(dialog.breaks)
        XCTAssertTrue(dialog.arguments.contains("--break-profiles"))
    }

    func testInUseNamesProfileConfigAndBreaks() throws {
        let dialog = try VaultRmPlan.parse(Data(inUseJSON.utf8)).confirmation(home: home)
        XCTAssertEqual(dialog.title, "mcp-okta/TOKEN is in use")
        XCTAssertEqual(dialog.button, "Delete and Break mcp-okta")
        XCTAssertTrue(dialog.breaks, "Cancel is the default")
        XCTAssertEqual(dialog.arguments, ["vault", "rm", "--break-profiles", "--yes", "mcp-okta/TOKEN"])
        XCTAssertEqual(dialog.paths, ["mcp-okta/TOKEN"])
        XCTAssertTrue(dialog.message.contains("profile mcp-okta (global) uses it"), dialog.message)
        XCTAssertTrue(dialog.message.contains("   started by ~/Security-Ops/.mcp.json"), dialog.message)
        XCTAssertTrue(dialog.message.contains("After this, mcp-okta won't start, and neither will the tools "
                + "~/Security-Ops/.mcp.json starts with it: a profile missing a secret can't start its tool."), dialog.message)
        XCTAssertTrue(dialog.message.contains("jit vault rm --break-profiles --yes mcp-okta/TOKEN"), dialog.message)
        XCTAssertFalse(dialog.message.contains("launch"), dialog.message)
    }

    /// jit 2.0 names the tools too: each by name and config, and the
    /// sentence names them rather than their config.
    func testInUseNamesTheTools() throws {
        let second = #",{"name":"okta-admin","config":"/Users/me/.claude.json"}"#
        let json = #"""
        {"paths":["mcp-okta/TOKEN"],
         "in_use":[{"path":"mcp-okta/TOKEN","profile":"mcp-okta","scope":"global",
                    "launched_by":["/Users/me/Security-Ops/.mcp.json"],
                    "tools":[{"name":"okta-mcp-server","config":"/Users/me/Security-Ops/.mcp.json"}\#(second)]}],
         "refused":true}
        """#
        let plan = try VaultRmPlan.parse(Data(json.utf8))
        XCTAssertEqual(plan.users.first?.tools, [
            VaultRmTool(name: "okta-mcp-server", config: "/Users/me/Security-Ops/.mcp.json"),
            VaultRmTool(name: "okta-admin", config: "/Users/me/.claude.json")
        ])
        let dialog = plan.confirmation(home: home)
        XCTAssertTrue(dialog.message.contains("• profile mcp-okta (global) uses it\n"
                + "   tool okta-mcp-server in ~/Security-Ops/.mcp.json\n   tool okta-admin in ~/.claude.json"), dialog.message)
        XCTAssertFalse(dialog.message.contains("started by"), "the tools say it; the configs are not said twice")
        XCTAssertTrue(dialog.message.contains("After this, mcp-okta won't start, and neither will tools okta-mcp-server "
                + "and okta-admin: a profile missing a secret can't start its tool."), dialog.message)
        let one = try VaultRmPlan.parse(Data(json.replacingOccurrences(of: second, with: "").utf8)).confirmation(home: home)
        XCTAssertTrue(one.message.contains("neither will tool okta-mcp-server:"), one.message)
    }

    func testCleanRunsThePlainDelete() throws {
        let plan = try VaultRmPlan.parse(Data(#"{"paths":["gh/TOKEN"],"refused":false}"#.utf8))
        let dialog = plan.confirmation(home: home)
        XCTAssertEqual(dialog.title, "Delete gh/TOKEN?")
        XCTAssertEqual(dialog.button, "Delete")
        XCTAssertFalse(dialog.breaks)
        XCTAssertEqual(dialog.arguments, ["vault", "rm", "--yes", "gh/TOKEN"])
        XCTAssertFalse(dialog.arguments.contains("--break-profiles"))
        XCTAssertTrue(dialog.message.contains("No profile, mount or pointer file jit can find uses it."), dialog.message)
    }

    /// A group argument deletes exactly what the dry run expanded it to.
    func testGroupDeletesTheExpandedPaths() throws {
        let plan = try VaultRmPlan.parse(Data(#"{"paths":["g/A","g/B","g/C"],"refused":false}"#.utf8))
        let dialog = plan.confirmation(home: home)
        XCTAssertEqual(dialog.title, "Delete 3 secrets?")
        XCTAssertEqual(dialog.button, "Delete 3")
        XCTAssertEqual(dialog.arguments, ["vault", "rm", "--yes", "g/A", "g/B", "g/C"])
    }

    func testPlanErrorRequiresTheBreakVariant() throws {
        let plan = try VaultRmPlan.parse(Data(#"{"paths":["a/B"],"refused":true,"error":"permission denied"}"#.utf8))
        let dialog = plan.confirmation(home: home)
        XCTAssertEqual(dialog.title, "jit can't tell what uses a/B")
        XCTAssertEqual(dialog.button, "Delete Anyway")
        XCTAssertTrue(dialog.breaks)
        XCTAssertEqual(dialog.arguments, ["vault", "rm", "--break-profiles", "--yes", "a/B"])
        XCTAssertTrue(dialog.message.contains("permission denied"), dialog.message)
    }

    func testPointerFileMountAndSeveralUsers() throws {
        let json = #"""
        {"paths":["aws/KEY","aws/SECRET","other/X"],
         "in_use":[
           {"path":"aws/KEY","profile":"aws","scope":"project","project":"/Users/me/infra","mount":"/Users/me/infra/.env"},
           {"path":"aws/SECRET","profile":"aws","scope":"project","project":"/Users/me/infra","mount":"/Users/me/infra/.env"},
           {"path":"aws/KEY","pointer_file":"/Users/me/.clisso.yaml"}],
         "refused":true}
        """#
        let dialog = try VaultRmPlan.parse(Data(json.utf8)).confirmation(home: home)
        XCTAssertEqual(dialog.title, "2 of these 3 secrets are in use")
        XCTAssertEqual(dialog.button, "Delete and Break 1 Profile and 1 File")
        XCTAssertTrue(dialog.message.contains("profile aws (project ~/infra) uses 2 of them"), dialog.message)
        XCTAssertTrue(dialog.message.contains("served by the mount at ~/infra/.env"), dialog.message)
        XCTAssertTrue(dialog.message.contains("~/.clisso.yaml points at aws/KEY (jit://)"), dialog.message)
        XCTAssertTrue(dialog.message.contains("jit migrate remove ~/infra/.env"), dialog.message)
    }

    func testNothingStoredOffersNothing() throws {
        let plan = try VaultRmPlan.parse(Data(#"{"paths":[],"missing":["x/Y"],"refused":false}"#.utf8))
        let dialog = plan.confirmation(home: home)
        XCTAssertNil(dialog.button)
        XCTAssertTrue(dialog.arguments.isEmpty)
    }

    /// jit 1.8 has no --dry-run: fail closed, say why, delete nothing.
    func testOlderJitFailsClosed() {
        let dialog = VaultRmPlan.unavailable(["a/B"], reason: "unknown flag: --dry-run")
        XCTAssertNil(dialog.button)
        XCTAssertTrue(dialog.arguments.isEmpty)
        XCTAssertTrue(dialog.message.hasPrefix("Nothing was deleted."), dialog.message)
        XCTAssertTrue(dialog.message.contains("older than 1.9"), dialog.message)
        XCTAssertThrowsError(try VaultRmPlan.parse(Data("unknown flag: --dry-run".utf8)))
    }

    func testRefusalIsRecognisedAndShownVerbatim() {
        let output = "! profile mcp-jamf (global) uses all 3\n  └ launched by ~/Security-Ops/.mcp.json\n"
            + "jit vault rm: nothing deleted, 3 secrets are in use"
        XCTAssertTrue(VaultRmPlan.isRefusal(output))
        XCTAssertTrue(VaultRmPlan.refusalMessage(output).hasSuffix(output))
        XCTAssertFalse(VaultRmPlan.isRefusal("jit vault rm: touch id cancelled"))
    }
}
