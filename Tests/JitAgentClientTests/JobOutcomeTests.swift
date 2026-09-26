// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// jit says what a run that did not happen means for its job in a field
/// (`job_outcome` on the event, `stopped` and `outcome` on `job_list`), so
/// the app decides from that and never from the word "refused". A jit older
/// than the fields is read exactly as before. Fixtures are the Go output
/// (JobsFixtures.swift).
final class JobOutcomeTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func event(_ json: String) throws -> SessionEvent {
        try decode(SessionEvent.self, json)
    }

    private let ago: (Date) -> String = { _ in "2 minutes ago" }

    // MARK: - Decode

    func testOutcomeFieldsDecode() throws {
        let jobs = try XCTUnwrap(try decode(AgentResponse.self, JobsFixture.outcomeList).jobs)
        XCTAssertEqual(jobs.map(\.name), ["notion-guests", "linear-issues", "wiz-inventory", "gh-audit"])
        XCTAssertEqual(jobs.map(\.stopped), [false, false, true, false])
        XCTAssertEqual(jobs.map(\.outcome), ["persisting-skip", "skip", "stop", nil])
        XCTAssertEqual(jobs.map(\.jobOutcome), [.persistingSkip, .skip, .stop, nil])
        XCTAssertEqual(jobs[0].skips, 3)
        XCTAssertEqual(jobs[0].skippingSinceUnix, 1_790_320_000)
        XCTAssertEqual(jobs[1].skips, 1)

        XCTAssertEqual(try event(JobsFixture.stopEvent).jobOutcome, "stop")
        XCTAssertEqual(try event(JobsFixture.stillStoppedEvent).jobOutcome, "still-stopped")
        XCTAssertEqual(try event(JobsFixture.skipEvent).jobOutcome, "skip")
        XCTAssertEqual(try event(JobsFixture.persistingSkipEvent).jobOutcome, "persisting-skip")
    }

    /// An older jit sends none of the fields, and still decodes.
    func testAnOlderJitsListDecodesWithoutThem() throws {
        let jobs = try XCTUnwrap(try decode(AgentResponse.self, JobsFixture.list).jobs)
        XCTAssertEqual(jobs.map(\.stopped), [nil, nil])
        XCTAssertEqual(jobs.map(\.outcome), [nil, nil])
        XCTAssertNil(try event(JobsFixture.pending).jobOutcome)
    }

    // MARK: - The notification

    func testAStopIsAnnounced() throws {
        let notice = try XCTUnwrap(try JobNotice(event: event(JobsFixture.stopEvent)))
        XCTAssertEqual(notice.kind, .stopped)
        XCTAssertEqual(notice.title, "notion-guests stopped running")
        XCTAssertEqual(notice.body, "List_guest_users.py changed since you approved it. Click to review.")
        XCTAssertEqual(notice.id, "job-stopped-notion-guests")
    }

    /// The stop was told when it happened; a retry of the stopped job is
    /// nothing new, though its cause still says "refused".
    func testARunOfAJobAlreadyStoppedIsNotAnnounced() throws {
        let still = try event(JobsFixture.stillStoppedEvent)
        XCTAssertTrue(still.cause?.contains("refused") == true, "the word alone would have announced it")
        XCTAssertNil(JobNotice(event: still))
    }

    func testALoneSkipIsNotAnnounced() throws {
        XCTAssertNil(try JobNotice(event: event(JobsFixture.skipEvent)))
    }

    /// Skipped runs that went on: the job is not stopped, but its owner
    /// should learn it has not been running, in jit's own sentence.
    func testSkipsThatWentOnAreAnnounced() throws {
        let notice = try XCTUnwrap(try JobNotice(event: event(JobsFixture.persistingSkipEvent)))
        XCTAssertEqual(notice.kind, .notRunning)
        XCTAssertEqual(notice.title, "notion-guests hasn't been running")
        XCTAssertEqual(
            notice.body,
            "Didn't run 3 times in a row since Sep 26 09:14, the job's key couldn't be loaded (the key can't be used right now). " +
                "It wasn't stopped: the next run tries again."
        )
        XCTAssertEqual(notice.id, "job-not-running-notion-guests")
    }

    /// A jit older than `job_outcome`: the word "refused" decides, and the
    /// notification is what it always was.
    func testAnOlderJitIsReadFromItsCauseAsBefore() throws {
        var old = try event(JobsFixture.stopEvent)
        old.jobOutcome = nil
        let notice = try XCTUnwrap(JobNotice(event: old))
        XCTAssertEqual(notice.title, "notion-guests stopped running")
        XCTAssertEqual(notice.body, "List_guest_users.py changed since you approved it. Click to review.")
        XCTAssertEqual(notice.id, "job-stopped-notion-guests")

        var retried = try event(JobsFixture.stillStoppedEvent)
        retried.jobOutcome = nil
        XCTAssertEqual(
            JobNotice(event: retried)?.body, "Stopped: list_guest_users.py changed since you approved it. Click to review.",
            "unchanged, retries included, until jit says otherwise"
        )

        var skipped = try event(JobsFixture.persistingSkipEvent)
        skipped.jobOutcome = nil
        XCTAssertNil(JobNotice(event: skipped), "no \"refused\", no notice, as before")
    }

    /// An outcome this app does not know is not guessed at from words.
    func testAnUnknownOutcomeIsNotAnnounced() throws {
        var future = try event(JobsFixture.stopEvent)
        future.jobOutcome = "paused"
        XCTAssertNil(JobNotice(event: future))
    }

    // MARK: - The row

    func testARowShowsSkipsThatWentOnAndNothingForOne() throws {
        let jobs = try XCTUnwrap(try decode(AgentResponse.self, JobsFixture.outcomeList).jobs)
        XCTAssertEqual(jobs.map(\.rowState), [.notRunning, .ready, .stopped, .ready])
        XCTAssertEqual(
            JobsWording.fact(jobs[0], ago: ago),
            "Hasn't run the last 3 times: the job's key couldn't be loaded (the key can't be used right now) · asks each time"
        )
        XCTAssertEqual(
            JobsWording.fact(jobs[1], ago: ago),
            "Claude ran it 2 minutes ago · worked · runs without asking",
            "a lone skip adds nothing"
        )

        let board = JobsBoard(jobs: jobs)
        XCTAssertEqual(board.stopped.map(\.name), ["wiz-inventory"])
        XCTAssertEqual(board.ready.map(\.name), ["gh-audit", "linear-issues", "notion-guests"], "not running is not stopped")
        XCTAssertEqual(board.needsYou, 1)
    }

    /// jit's `stopped` decides when it is sent; `state` only for an older jit.
    func testStoppedIsReadFromJitsFieldWhenSent() throws {
        var job = JobStatus(name: "n", dir: "/d", argv: ["a"], state: "changed")
        XCTAssertEqual(job.rowState, .stopped, "an older jit: from state, as before")
        job.stopped = false
        XCTAssertEqual(job.rowState, .ready)
        XCTAssertTrue(JobsBoard(jobs: [job]).stopped.isEmpty)

        let old = try XCTUnwrap(try decode(AgentResponse.self, JobsFixture.list).jobs)
        XCTAssertEqual(old.map(\.rowState), [.ready, .stopped])
    }

    /// Without a count, or with one, the words never read "the last 1 times".
    func testNotRunningWordsWithoutACountOrAReason() {
        var job = JobStatus(name: "n", dir: "/d", argv: ["a"], state: "ready")
        job.outcome = "persisting-skip"
        XCTAssertEqual(JobsWording.notRunning(job), "Hasn't run the last few times")
        job.skips = 1
        job.lastRefusal = "the job's key couldn't open NOTION_API_KEY (the key can't be used right now)"
        XCTAssertEqual(
            JobsWording.notRunning(job),
            "Hasn't run the last few times: the job's key couldn't open NOTION_API_KEY (the key can't be used right now)"
        )
    }
}
