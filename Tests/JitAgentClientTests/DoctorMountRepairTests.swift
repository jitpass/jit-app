// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The two repairs a project record makes possible, as the window shows
/// them: a project that moved, and a copy this Mac does not serve.
final class DoctorMountRepairTests: XCTestCase {
    private func item(_ kind: String, command: String, argv: [String], needs: String? = nil) -> DoctorItem {
        DoctorItem(
            kind: kind, scope: "mount", profile: nil, variable: nil,
            path: "/Users/me/old/.env", detail: "d", action: "`\(command)`",
            fixes: [DoctorFix(command: command, argv: argv, destructive: false, presence: false, needs: needs)]
        )
    }

    func testMovedProjectOffersOneClickRepointing() {
        let moved = item("mount_moved", command: "jit mount relocate ~/work/hibob", argv: ["mount", "relocate", "/Users/me/work/hibob"])
        let actions = DoctorAdvice.actions(for: moved)
        XCTAssertEqual(actions.map(\.title), ["Update Location"])
        XCTAssertEqual(actions.first?.argv, [["mount", "relocate", "/Users/me/work/hibob", "--yes"]])
        // It edits the registry and nothing else, so it must not confirm or
        // ask for Touch ID — the guard that makes a project record safe is
        // that acting on one costs a registry line, not a secret.
        XCTAssertFalse(actions.first?.destructive ?? true)
        XCTAssertFalse(actions.first?.presence ?? true)
        XCTAssertEqual(actions.first?.needs, .nothing)
    }

    func testUnregisteredMountOffersToServeIt() {
        let copy = item(
            "mount_unregistered",
            command: "jit mount register ~/scripts/hibob2",
            argv: ["mount", "register", "/Users/me/scripts/hibob2"]
        )
        let actions = DoctorAdvice.actions(for: copy)
        XCTAssertEqual(actions.map(\.title), ["Serve This File"])
        XCTAssertEqual(actions.first?.argv, [["mount", "register", "/Users/me/scripts/hibob2", "--yes"]])
        XCTAssertFalse(actions.first?.destructive ?? true)
    }

    /// An ambiguous relocation names no project — doctor refuses to choose
    /// between two candidates. A placeholder must not become a button that
    /// looks like it will finish the job.
    func testAmbiguousRelocationOffersNoButton() {
        let ambiguous = item(
            "mount_moved", command: "jit mount relocate <project>",
            argv: ["mount", "relocate", "<project>"], needs: "<project>"
        )
        XCTAssertEqual(DoctorAdvice.actions(for: ambiguous), [])
    }

    /// Both kinds say what they are. Without an entry in the titles table a
    /// kind renders as a bare capitalized version of jit's internal noun,
    /// with no explanation — the defect that made a red card read
    /// "Stale Pointers" and say nothing else.
    func testBothKindsAreNamedAndExplained() {
        for kind in ["mount_moved", "mount_unregistered"] {
            let group = DoctorAdvice.groups([item(kind, command: "jit mount register ~/x", argv: ["mount", "register", "/x"])])[0]
            XCTAssertFalse(group.title.contains("_"), "\(kind) title = \(group.title)")
            XCTAssertNotEqual(group.title, kind.replacingOccurrences(of: "_", with: " ").capitalized, "\(kind) fell through")
            XCTAssertNotNil(group.note, "\(kind) has no explanation")
        }
    }
}
