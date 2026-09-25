// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class JobReviewTests: XCTestCase {
    private var job: JobStatus {
        var job = JobStatus(name: "wiz", dir: "/Users/x/wiz", argv: ["python", "inventory.py"], ask: "never", state: "changed")
        job.exe = "/Users/x/.local/uv/python3.14"
        job.profile = "wiz"
        job.outputs = ["/Users/x/reports"]
        job.description = "Inventory"
        job.secrets = [JobSecretStatus(name: "WIZ_ID", path: "wiz/ID", shown: true), JobSecretStatus(name: "WIZ_KEY", path: "wiz/KEY")]
        job.changes = [
            JobChange(path: "inventory.py", kind: "changed"),
            JobChange(path: "outside:/Users/x/shared/lib.py", kind: "rewritten"),
            JobChange(path: "run.py (its target)", kind: "changed"),
            JobChange(path: "(the program itself)", kind: "changed"),
            JobChange(path: "old.py", kind: "removed")
        ]
        return job
    }

    func testItemsNameTheFileToOpen() {
        let items = JobReview(job: job).items
        XCTAssertEqual(items.map(\.file), [
            "/Users/x/wiz/inventory.py", "/Users/x/shared/lib.py", "/Users/x/wiz/run.py", "/Users/x/.local/uv/python3.14", nil
        ])
        XCTAssertEqual(items[3].label, "python3.14 (the program itself)")
    }

    /// Approving again keeps every setting: dropping the shown list would
    /// hide a value the human chose to show (the CLI's reapprove line had
    /// exactly that bug once).
    func testReapprovalKeepsEverySetting() {
        let spec = JobReview(job: job).reapproval(pathEnv: "/usr/bin", home: "/Users/x")
        XCTAssertEqual(spec.dir, "/Users/x/wiz")
        XCTAssertEqual(spec.argv, ["python", "inventory.py"])
        XCTAssertEqual(spec.profile, GrantProfile(name: "wiz", root: "/Users/x/wiz"))
        XCTAssertEqual(spec.ask, "never")
        XCTAssertEqual(spec.shown, ["WIZ_ID"])
        XCTAssertEqual(spec.outputs, ["/Users/x/reports"])
        XCTAssertEqual(spec.description, "Inventory")
        XCTAssertEqual(spec.replace, true)
    }
}
