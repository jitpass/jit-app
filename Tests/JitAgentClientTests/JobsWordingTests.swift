// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The AI Jobs window's sentences say only what the code knows, in
/// sentence case.
final class JobsWordingTests: XCTestCase {
    private func job(ask: String, state: JobState = .ready) -> JobStatus {
        JobStatus(name: "notion-guests", dir: "/d", argv: ["python", "a.py"], ask: ask, state: state.rawValue)
    }

    private let ago: (Date) -> String = { _ in "2 minutes ago" }

    /// The empty window is about jobs only: a standing grant can still
    /// hand a tool a secret, so it never says no tool can.
    func testTheEmptyWindowSpeaksOnlyOfJobs() {
        XCTAssertEqual(JobsWording.emptyTitle, "No AI jobs yet")
        XCTAssertFalse(JobsWording.emptyTitle.contains("secret"))
    }

    /// Only the line's first word is capitalised: "Asks each time" in the
    /// middle of the row read as a new sentence.
    func testAJobsRowIsSentenceCase() {
        XCTAssertEqual(JobsWording.fact(job(ask: "never"), ago: ago), "Not run yet · runs without asking")
        XCTAssertEqual(JobsWording.fact(job(ask: "each-time"), ago: ago), "Not run yet · asks each time")

        var ran = job(ask: "never")
        ran.lastRunUnix = 1_790_310_000
        ran.lastCaller = "Claude"
        ran.lastExit = 0
        ran.lastHidden = 1
        ran.secrets = [JobSecretStatus(name: "NOTION_API_KEY", path: "notion/NOTION_API_KEY")]
        XCTAssertEqual(
            JobsWording.fact(ran, ago: ago),
            "Claude ran it 2 minutes ago · worked · hid 1 value · runs without asking · 1 secret"
        )

        var refused = job(ask: "each-time", state: .changed)
        refused.lastCaller = "Claude"
        XCTAssertEqual(JobsWording.fact(refused, ago: ago), "Refused Claude · asks each time")
    }

    /// Installed but unable to start: the app can't tell a jit that is
    /// gone from one older than AI jobs, so it says both, as the CLI does.
    func testAnEntryThatCantStartNamesBothCauses() {
        let broken = MCPStatus(client: "cursor", installed: true, command: "/opt/old/jit", runnable: false)
        XCTAssertEqual(JobsWording.mcpFact(.cursor, broken), "Set up for a jit that is gone, or older than AI jobs")
        XCTAssertEqual(JobsWording.mcpFact(.cursor, MCPStatus(client: "cursor", installed: false)), "Not connected")
        XCTAssertEqual(
            JobsWording.mcpFact(.cursor, MCPStatus(client: "cursor", installed: true, runnable: true)),
            "Connected · its agent asks through jit mcp"
        )
        XCTAssertEqual(JobsWording.mcpFact(.cursor, nil), "Checking…")
    }
}
