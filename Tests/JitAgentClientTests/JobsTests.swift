// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// AI Jobs on the wire, against fixtures produced from the Go types
/// (JobsFixtures.swift): the rule is to mirror the protocol, never fork it,
/// and a hand-typed fixture only proves the Swift agrees with whoever typed
/// it.
final class JobsTests: XCTestCase {
    private var path = ""

    override func setUp() {
        path = NSTemporaryDirectory() + "jitpass-test-\(UUID().uuidString.prefix(8)).sock"
    }

    override func tearDown() {
        unlink(path)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testJobListDecodes() throws {
        let response = try decode(
            AgentResponse.self,
            JobsFixture.list
        )
        let jobs = try XCTUnwrap(response.jobs)
        XCTAssertEqual(jobs.map(\.name), ["notion-guests", "wiz-inventory"])
        let notion = jobs[0]
        XCTAssertEqual(notion.jobState, .ready)
        XCTAssertTrue(notion.asksEachTime)
        XCTAssertEqual(notion.files, 242)
        XCTAssertEqual(notion.lastCaller, "Claude")
        XCTAssertEqual(notion.secrets?.map(\.name), ["INTERNAL_DOMAINS", "NOTION_API_KEY"])
        XCTAssertEqual(notion.secrets?.map(\.isShown), [true, false])
        let wiz = jobs[1]
        XCTAssertEqual(wiz.jobState, .changed)
        XCTAssertFalse(wiz.asksEachTime)
        XCTAssertEqual(wiz.changes, [JobChange(path: "inventory.py", kind: "changed")])
        XCTAssertEqual(wiz.lastRefusal, "inventory.py changed since you approved it")
    }

    func testPreviewAndRefusalDecode() throws {
        let preview = try XCTUnwrap(try decode(
            AgentResponse.self,
            JobsFixture.preview
        ).preview)
        XCTAssertNil(preview.refusal)
        XCTAssertEqual(preview.program, "list_guest_users.py")
        XCTAssertEqual(preview.prompt, "let AI run notion/list_guest_users.py with 1 notion secret")
        let refused = try XCTUnwrap(try decode(
            AgentResponse.self,
            JobsFixture.refused
        ).preview)
        XCTAssertEqual(refused.refusal?.hasPrefix("job_allow: python3 -c runs a program"), true)
    }

    func testProposalAndEventsDecode() throws {
        let proposal = try XCTUnwrap(try decode(
            AgentResponse.self,
            JobsFixture.proposals
        ).proposals?.first)
        XCTAssertEqual(proposal.id, "c-1a2b3c4d")
        XCTAssertEqual(proposal.spec.argv, [".venv/bin/python", "list_guest_users.py"])
        XCTAssertEqual(proposal.spec.profile?.name, "notion")
        XCTAssertEqual(proposal.launchedBy, "Claude")
        let pending = try decode(
            SessionEvent.self,
            JobsFixture.pending
        )
        XCTAssertEqual(pending.op, SessionEvent.jobRunOp)
        XCTAssertEqual(pending.job, "notion-guests")
        XCTAssertNotNil(ConsentRequest(event: pending), "a job run is brokered like any disclosed prompt")
        let offered = try decode(
            SessionEvent.self,
            JobsFixture.proposalEvent
        )
        XCTAssertEqual(offered.kind, SessionEvent.jobProposalKind)
        XCTAssertEqual(offered.consentID, "c-1a2b3c4d")
    }

    /// What the app sends for an approval is, key for key, what the Go
    /// request marshals to.
    func testAllowRequestMatchesTheGoWire() throws {
        let spec = JobSpec(
            dir: "/d", argv: ["python", "a.py"], profile: GrantProfile(name: "notion", root: "/d"),
            ask: JobAsk.eachTime.rawValue, shown: ["INTERNAL_DOMAINS"], outputs: ["/r"],
            pathEnv: "/usr/bin", home: "/Users/x", description: "d", replace: true
        )
        let request = AgentRequest(op: .jobAllow, jobName: "notion-guests", jobSpec: spec, proposalID: "c-1a2b3c4d")
        let ours = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? NSDictionary
        let go = try JSONSerialization
            .jsonObject(
                with: Data(JobsFixture.allowReq
                    .utf8)
            ) as? NSDictionary
        XCTAssertEqual(ours, go)
    }

    func testJobCallsSendTheRightOps() throws {
        let seen = Locked<[AgentRequest]>([])
        let server = try FakeAgent(path: path) { request in
            seen.append(request)
            switch request.op {
            case .jobList: return JobsFixture.list
            case .jobPreview: return JobsFixture.preview
            case .jobProposals: return JobsFixture.proposals
            case .jobAllow: return #"{"ok":true,"jobs":[{"name":"notion-guests","dir":"/d","argv":["python","a.py"]}]}"#
            default: return #"{"ok":true}"#
            }
        }
        defer { server.stop() }
        let client = AgentClient(socketPath: path, timeout: 2)
        XCTAssertEqual(try client.jobs().count, 2)
        let spec = JobSpec(dir: "/d", argv: ["python", "a.py"], pathEnv: "/usr/bin", home: "/Users/x")
        XCTAssertEqual(try client.previewJob(name: "notion-guests", spec: spec).files, 242)
        XCTAssertEqual(try client.allowJob(name: "notion-guests", spec: spec, proposalID: "c-1").name, "notion-guests")
        try client.removeJob(name: "notion-guests")
        XCTAssertEqual(try client.jobProposals().count, 1)
        try client.dismissProposal(id: "c-1")
        let requests = seen.value
        XCTAssertEqual(requests.map(\.op), [.jobList, .jobPreview, .jobAllow, .jobRemove, .jobProposals, .jobDismiss])
        XCTAssertEqual(requests[2].proposalID, "c-1")
        XCTAssertEqual(requests[3].jobName, "notion-guests")
        XCTAssertEqual(requests[5].proposalID, "c-1")
    }

    /// The first Cowork run showed a job's run as "use a credential once,
    /// remembered until the vault locks", which is false for a job.
    func testJobRunPromptSaysThisRunOnly() throws {
        let request = try XCTUnwrap(ConsentRequest(event: decode(SessionEvent.self, JobsFixture.pending)))
        XCTAssertTrue(request.isJobRun)
        XCTAssertEqual(request.job, "notion-guests")
        XCTAssertFalse(request.purpose.contains("remembered"))
        XCTAssertTrue(request.purpose.contains("asks again next time"))
    }
}
