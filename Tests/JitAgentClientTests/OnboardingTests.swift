// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class OnboardingTests: XCTestCase {
    func testAQuickScanLeavesTheGuardedFoldersAlone() {
        XCTAssertEqual(
            QuickScan.excludes(home: "/Users/alex"),
            ["/Users/alex/Desktop", "/Users/alex/Documents", "/Users/alex/Downloads"]
        )
    }

    /// The vault must exist before anything writes to it, and the rescan
    /// closes the list so the final number is measured.
    func testTheVaultComesFirstAndTheRescanLast() {
        let plan = ProtectPlan(migrate: ["/Users/alex/.env", "/Users/alex/.npmrc"], wrap: ["gh"])
        let tasks = OnboardingPlan.tasks(plan: plan, createsVault: true)
        XCTAssertEqual(tasks.map(\.kind), [.createVault, .migrate, .wrap("gh"), .rescan])
        XCTAssertEqual(tasks[0].command, ["vault", "init"])
        XCTAssertEqual(tasks[1].command, ["migrate", "/Users/alex/.env", "/Users/alex/.npmrc", "--yes"])
        XCTAssertEqual(tasks[2].command, ["wrap", "gh"])
        XCTAssertNil(tasks[3].command)
    }

    func testAnExistingVaultIsNotCreatedAgain() {
        let tasks = OnboardingPlan.tasks(plan: ProtectPlan(migrate: ["/a/.env"]), createsVault: false)
        XCTAssertEqual(tasks.map(\.kind), [.migrate, .rescan])
    }

    /// Nothing migratable on a new Mac: the vault alone, then the rescan.
    func testNothingToProtectStillCreatesTheVault() {
        let tasks = OnboardingPlan.tasks(plan: ProtectPlan(), createsVault: true)
        XCTAssertEqual(tasks.map(\.kind), [.createVault, .rescan])
    }

    func testNothingToDoIsNoTasksAtAll() {
        XCTAssertTrue(OnboardingPlan.tasks(plan: ProtectPlan(), createsVault: false).isEmpty)
    }

    func testTheOnePasswordSwitchOffPassesTheFlag() {
        let tasks = OnboardingPlan.tasks(plan: ProtectPlan(migrate: ["/a/.env"]), createsVault: false, linkOnePassword: false)
        XCTAssertEqual(tasks[0].command, ["migrate", "/a/.env", "--yes", "--no-1password"])
    }

    /// The 1Password check is the slow part of a migrate, so the row that
    /// waits on it says so, and a run without it does not mention it.
    func testTheMigrateRowWarnsOnlyWhenOnePasswordIsChecked() {
        let plan = ProtectPlan(migrate: ["/a/.env"])
        let linked = OnboardingPlan.tasks(plan: plan, createsVault: false, linkOnePassword: true)
        let plain = OnboardingPlan.tasks(plan: plan, createsVault: false, linkOnePassword: false)
        XCTAssertTrue(linked[0].detail.contains("1Password"))
        XCTAssertFalse(plain[0].detail.contains("1Password"))
    }

    func testCommandLinesReadLikeTheTerminal() {
        let tasks = OnboardingPlan.tasks(plan: ProtectPlan(migrate: ["/Users/alex/code/.env"], wrap: ["aws"]), createsVault: true)
        XCTAssertEqual(
            OnboardingPlan.commandLines(tasks, home: "/Users/alex"),
            ["jit vault init", "jit migrate ~/code/.env --yes", "jit wrap aws"]
        )
    }
}
