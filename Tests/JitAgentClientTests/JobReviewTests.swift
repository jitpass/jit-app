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

    /// An approval by an older jit reports a pseudo-path and a phrase for a
    /// kind. The phrase was the row's chip and wrapped a letter or two a
    /// line; the pseudo-path offered Open File on a file that isn't there
    /// (2026-09-27).
    func testUncheckedIsNotAFileAndHasAShortChip() {
        var job = job
        job.changes = [JobChange(path: JobChange.libsPath, kind: JobChange.unchecked)]
        let item = JobReview(job: job).items[0]
        XCTAssertNil(item.file)
        XCTAssertEqual(item.label, "What the program loads from outside the folder")
        XCTAssertEqual(item.badge, "not checked")
        XCTAssertNotNil(item.note)
    }

    /// A library outside the folder is reported by its absolute path, not
    /// under the job's folder.
    func testLibraryChangesOpenTheirOwnPath() {
        var job = job
        job.changes = [
            JobChange(path: "/opt/py/lib/os.py", kind: "changed"),
            JobChange(path: "/opt/py/lib", kind: JobChange.folderChanged)
        ]
        let items = JobReview(job: job).items
        XCTAssertEqual(items.map(\.file), ["/opt/py/lib/os.py", "/opt/py/lib"])
        XCTAssertEqual(items.map(\.badge), ["changed", "changed"])
        XCTAssertNil(items[0].note)
        XCTAssertNotNil(items[1].note)
    }

    /// Every chip is one word or two, whatever jit's kind; and the stop's
    /// clause says "since you approved it" once.
    func testChipsAreShortAndSentencesSayItOnce() {
        let kinds = ["changed", "added", "removed", "rewritten", JobChange.unchecked, JobChange.folderChanged, JobChange.folderRewritten]
        for kind in kinds {
            let change = JobChange(path: JobChange.libsPath, kind: kind)
            XCTAssertLessThanOrEqual(change.badge.split(separator: " ").count, 2, kind)
            XCTAssertLessThanOrEqual(change.sentence.components(separatedBy: "since you approved it").count, 2, kind)
        }
        XCTAssertFalse(JobChange(path: JobChange.libsPath, kind: JobChange.unchecked).sentence.contains(JobChange.libsPath))
    }
}
