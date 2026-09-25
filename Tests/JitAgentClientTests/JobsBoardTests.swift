// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class JobsBoardTests: XCTestCase {
    private func job(_ name: String, _ state: JobState, runs: Int64 = 0) -> JobStatus {
        var job = JobStatus(name: name, dir: "/d", argv: ["python", "a.py"], state: state.rawValue)
        job.runs = runs
        return job
    }

    private func proposal(_ id: String, at time: Int64) throws -> JobProposal {
        let json = #"{"id":"\#(id)","name":"p","spec":{"dir":"/d","argv":["a"],"path_env":"","home":""},"unix_time":\#(time)}"#
        return try JSONDecoder().decode(JobProposal.self, from: Data(json.utf8))
    }

    func testBoardSortsStoppedFromReady() throws {
        let board = try JobsBoard(
            jobs: [job("wiz", .changed, runs: 2), job("notion", .ready, runs: 3), job("hibob", .rotated)],
            proposals: [proposal("b", at: 2), proposal("a", at: 1)]
        )
        XCTAssertEqual(board.stopped.map(\.name), ["hibob", "wiz"])
        XCTAssertEqual(board.ready.map(\.name), ["notion"])
        XCTAssertEqual(board.proposals.map(\.id), ["a", "b"], "oldest proposal first")
        XCTAssertEqual(board.needsYou, 4)
        XCTAssertEqual(board.runs, 5)
    }

    func testPanelRow() throws {
        XCTAssertNil(PanelValue.aiJobs(JobsBoard(jobs: []), connected: false), "a Mac that never used AI Jobs sees no row")
        XCTAssertEqual(PanelValue.aiJobs(JobsBoard(jobs: []), connected: true), PanelValue.Row("none"))
        XCTAssertEqual(PanelValue.aiJobs(JobsBoard(jobs: [job("n", .ready)]), connected: false), PanelValue.Row("1 ready"))
        XCTAssertEqual(
            PanelValue.aiJobs(JobsBoard(jobs: [job("n", .ready), job("w", .changed)]), connected: true),
            PanelValue.Row("1 needs you", .amber)
        )
        XCTAssertEqual(
            try PanelValue.aiJobs(JobsBoard(jobs: [], proposals: [proposal("a", at: 1)]), connected: false),
            PanelValue.Row("1 needs you", .amber),
            "a waiting proposal alone shows the row"
        )
    }

    func testMCPStatusDecodesTheCLIOutput() throws {
        // `jit mcp status --format json`, as the Go struct marshals it.
        let json = #"{"client":"claude-desktop","config":"/c.json","installed":true,"command":"/opt/homebrew/bin/jit","runnable":false}"#
        let status = try JSONDecoder().decode(MCPStatus.self, from: Data(json.utf8))
        XCTAssertTrue(status.installed)
        XCTAssertFalse(status.isConnected, "an entry whose jit is gone is not connected")
    }
}

final class MCPAppTests: XCTestCase {
    /// The ids are jit's `--client` values; a drift would connect nothing.
    func testIDsAreJitsClientValues() {
        XCTAssertEqual(MCPApp.allCases.map(\.rawValue), ["claude-desktop", "cursor"])
        XCTAssertEqual(MCPApp.cursor.arguments("install"), ["mcp", "install", "--client", "cursor"])
    }
}
