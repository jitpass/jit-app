// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class OffboardingTests: XCTestCase {
    /// The shape jit 1.8 prints, lists that are empty included: Go writes a
    /// nil slice as null, and a plan that fails to decode is a dead window.
    private let planJSON = """
    {"restore_plan":{"restore":[
      {"path":"/Users/u/.zshrc","kind":"shell"},
      {"path":"/Users/u/.aws/config","kind":"backup","drifted":true},
      {"path":"/Users/u/proj/.env","kind":"mount"}],
     "kept_clean":["/Users/u/.zsh_history"],"unwired":[],"gone":["/Users/u/old/.env"],
     "vault_only":[{"path":"stripe/key","class":"manual"},{"path":"gh/token","class":"wrap"},{"path":"x/y"}],
     "project_stores":["/Users/u/proj/.jit"]},
     "secrets":23,"key_present":true,"shims":["gh","aws"],"guard":true,"helpers":null,
     "path_line_file":"/Users/u/.zshrc"}
    """

    func testThePlanDecodesWithNullLists() throws {
        let plan = try UninstallPlan.parse(Data(planJSON.utf8))
        XCTAssertEqual(plan.restore.map(\.kind), ["shell", "backup", "mount"])
        XCTAssertEqual(plan.drifted.map(\.path), ["/Users/u/.aws/config"])
        XCTAssertEqual(plan.gone, ["/Users/u/old/.env"])
        XCTAssertEqual(plan.vaultOnly.count, 3)
        XCTAssertEqual(plan.helpers, [])
        XCTAssertTrue(plan.historyGuard)
        XCTAssertTrue(plan.keyPresent)
    }

    func testVaultOnlySecretsAreDescribedInAPersonsWords() throws {
        let plan = try UninstallPlan.parse(Data(planJSON.utf8))
        XCTAssertEqual(
            OffboardingPlan.describe(vaultOnly: plan.vaultOnly),
            "1 added by hand, 1 from protected tools, 1 from older setups"
        )
    }

    func testEventsParseAndUnknownLinesAreSkipped() {
        XCTAssertEqual(UninstallEvent.parse(line: #"{"event":"step","step":"restore"}"#), .step("restore"))
        XCTAssertEqual(
            UninstallEvent.parse(line: #"{"event":"file","path":"/a","ok":false,"error":"no"}"#),
            .file(path: "/a", error: "no")
        )
        XCTAssertEqual(
            UninstallEvent.parse(line: #"{"event":"failed","failures":[{"path":"/a","error":"no"}]}"#),
            .failed([.init(path: "/a", error: "no")])
        )
        XCTAssertEqual(UninstallEvent.parse(line: #"{"event":"done","ok":true}"#), .done(problems: []))
        XCTAssertNil(UninstallEvent.parse(line: #"{"event":"something-newer"}"#))
        XCTAssertNil(UninstallEvent.parse(line: "Removed the background service."))
    }

    func testTheChecklistFollowsTheEngineStepByStep() throws {
        let plan = try UninstallPlan.parse(Data(planJSON.utf8))
        var rows = OffboardingPlan.tasks(plan: plan, restoring: true)
        XCTAssertEqual(rows.map(\.id), ["auth", "restore", "stores", "tools", "vault", "app"])
        XCTAssertEqual(rows[1].title, "Put 3 files back")
        XCTAssertEqual(rows[3].title, "Stop the service, unprotect gh and aws")

        rows = OffboardingPlan.advance(rows, with: .step("auth"))
        XCTAssertEqual(rows[0].state, .running)
        rows = OffboardingPlan.advance(rows, with: .step("restore"))
        XCTAssertEqual(rows[0].state, .done)
        XCTAssertEqual(rows[1].state, .running)
        // "service" and "tools" are one row: the second must not restart it.
        rows = OffboardingPlan.advance(rows, with: .step("service"))
        rows = OffboardingPlan.advance(rows, with: .step("tools"))
        XCTAssertEqual(rows.map(\.state), [.done, .done, .done, .running, .pending, .pending])
        rows = OffboardingPlan.advance(rows, with: .done(problems: []))
        XCTAssertEqual(rows.last?.state, .pending, "the app's own row is the app's to finish")
        XCTAssertTrue(rows.dropLast().allSatisfy { $0.state == .done })
    }

    func testAFailedRestoreStopsTheListAtItsRow() throws {
        let plan = try UninstallPlan.parse(Data(planJSON.utf8))
        var rows = OffboardingPlan.tasks(plan: plan, restoring: true)
        rows = OffboardingPlan.advance(rows, with: .step("restore"))
        rows = OffboardingPlan.advance(rows, with: .failed([.init(path: "/a", error: "no"), .init(path: "/b", error: "no")]))
        XCTAssertEqual(rows[1].state, .failed("2 files could not be put back."))
        XCTAssertEqual(rows[2].state, .pending)
    }

    /// The one path that deletes without restoring has no restore rows.
    func testStartingOverHasNoRestoreRows() {
        var plan = UninstallPlan()
        plan.keyPresent = false
        XCTAssertEqual(OffboardingPlan.tasks(plan: plan, restoring: false).map(\.id), ["auth", "tools", "vault", "app"])
    }
}
