// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class JobDraftTests: XCTestCase {
    func testSplitIsShellLikeWithoutExpansion() {
        XCTAssertEqual(JobDraft.split(".venv/bin/python list_guest_users.py"), [".venv/bin/python", "list_guest_users.py"])
        XCTAssertEqual(JobDraft.split(#"python "my script.py" --out '$HOME/x'"#), ["python", "my script.py", "--out", "$HOME/x"])
        XCTAssertEqual(JobDraft.split(#"a\ b  c"#), ["a b", "c"])
        XCTAssertEqual(JobDraft.split(#"x "" y"#), ["x", "", "y"], "an empty quoted argument is still an argument")
        XCTAssertEqual(JobDraft.split("   "), [])
    }

    func testJoinRoundTrips() {
        for argv in [["python", "a.py"], ["python", "my script.py", "it's"], ["sh", "-c", "a;b"]] {
            XCTAssertEqual(JobDraft.split(JobDraft.join(argv)), argv)
        }
    }

    func testMissingNamesTheFirstGap() {
        var draft = JobDraft()
        XCTAssertEqual(draft.missing, "Choose the folder the job runs in")
        draft.folder = "/Users/x/notion"
        XCTAssertEqual(draft.missing, "Type the command, as you would in a terminal in that folder")
        draft.command = "python a.py"
        XCTAssertEqual(draft.missing, "Name the job")
        draft.name = "Notion Guests"
        XCTAssertEqual(draft.missing, "Name it with lowercase letters, digits and dashes")
        draft.name = "notion-guests"
        XCTAssertTrue(draft.isComplete)
    }

    func testSuggestedName() {
        XCTAssertEqual(JobDraft.suggestedName(folder: "/Users/x/custom_scripts/notion"), "notion")
        XCTAssertEqual(JobDraft.suggestedName(folder: "/Users/x/My Scripts"), "my-scripts")
    }

    /// A proposal opens at each-time whatever the agent asked for.
    func testProposalPrefillNeverStartsUnattended() throws {
        let json = #"{"id":"c-1","name":"notion-guests","spec":{"dir":"/n","argv":["python","a b.py"],"#
            + #""profile":{"name":"notion","root":"/n"},"ask":"never","path_env":"","home":""},"unix_time":1}"#
        let proposal = try JSONDecoder().decode(JobProposal.self, from: Data(json.utf8))
        let draft = JobDraft(proposal: proposal)
        XCTAssertEqual(draft.ask, .eachTime)
        XCTAssertEqual(draft.argv, ["python", "a b.py"])
        XCTAssertEqual(draft.profile, "notion")
        let spec = draft.spec(pathEnv: "/usr/bin", home: "/Users/x")
        XCTAssertEqual(spec.ask, "each-time")
        XCTAssertEqual(spec.profile, GrantProfile(name: "notion", root: "/n"))
    }
}
