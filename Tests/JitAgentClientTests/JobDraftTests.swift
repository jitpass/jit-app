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
        XCTAssertEqual(draft.missing, "Choose the profile whose secrets the script needs")
        draft.choose(profile: DiscoveredProfile(name: "notion", root: "/Users/x/notion", manifestPath: "/m", keys: ["K"]))
        XCTAssertEqual(draft.folder, "/Users/x/notion", "a project profile's folder is the job's")
        XCTAssertEqual(draft.missing, "Choose what the AI tool may run")
        draft.choose(script: JobScript(file: "list_guest_users.py", argv: [".venv/bin/python", "list_guest_users.py"]))
        XCTAssertEqual(draft.name, "notion-list-guest-users", "the name follows the script")
        XCTAssertTrue(draft.isComplete)
        draft.name = "Notion Guests"
        XCTAssertEqual(draft.missing, "Name it with lowercase letters, digits and dashes")
    }

    /// A global profile names no folder: one is chosen, and the spec sends
    /// no root, which is how the service reads the global store.
    func testGlobalProfileAsksForAFolderAndSendsNoRoot() {
        var draft = JobDraft()
        draft.choose(profile: DiscoveredProfile(name: "mcp-caido", root: nil, manifestPath: "/m", keys: ["K"]))
        XCTAssertEqual(draft.missing, "Choose the folder the job runs in")
        draft.folder = "/Users/x/tools"
        draft.command = "python3 a.py"
        XCTAssertNil(draft.spec(pathEnv: "", home: "").profile?.root)
        draft.choose(profile: DiscoveredProfile(name: "notion", root: "/n", manifestPath: "/m2", keys: ["K"]))
        XCTAssertEqual(draft.spec(pathEnv: "", home: "").profile?.root, "/n")
        XCTAssertTrue(draft.command.isEmpty, "a new profile drops the last folder's command")
    }

    /// Nothing is claimed before it is chosen: blanks stay blanks.
    func testSentenceLeavesBlanksUntilChosen() {
        var draft = JobDraft()
        XCTAssertEqual(draft.sentence(program: nil, secrets: nil), [
            .text("Let AI tools run "), .blank("a script"), .text(" with "), .blank("a profile's secrets"),
            .text(". They see what it prints, never the values.")
        ])
        draft.choose(profile: DiscoveredProfile(name: "notion", root: "/x/notion", manifestPath: "/m", keys: ["K"]))
        draft.command = ".venv/bin/python list_guest_users.py"
        XCTAssertEqual(draft.sentence(program: nil, secrets: 3)[1], .value("list_guest_users.py"))
        XCTAssertEqual(draft.sentence(program: nil, secrets: 3)[3], .value("notion"))
        XCTAssertEqual(draft.sentence(program: nil, secrets: 3)[5], .value("3 secrets"))
    }

    func testTypedNameStopsFollowingTheScript() {
        var draft = JobDraft()
        draft.choose(profile: DiscoveredProfile(name: "notion", root: "/x/notion", manifestPath: "/m", keys: []))
        draft.name = "guests"
        draft.nameSuggested = false
        draft.choose(script: JobScript(file: "setup.sh", argv: ["./setup.sh"]))
        XCTAssertEqual(draft.name, "guests")
    }

    func testSuggestedName() {
        XCTAssertEqual(JobDraft.suggestedName(folder: "/Users/x/custom_scripts/notion"), "notion")
        XCTAssertEqual(JobDraft.suggestedName(folder: "/Users/x/My Scripts"), "my-scripts")
        XCTAssertEqual(JobDraft.suggestedName(folder: "/x/notion", script: "list_guest_users.py"), "notion-list-guest-users")
        XCTAssertEqual(JobDraft.suggestedName(folder: "/x/notion", script: "notion_export.py"), "notion-export")
        XCTAssertEqual(JobDraft.suggestedName(folder: "/x/jamf", script: "jamf.sh"), "jamf")
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

    /// The top level only, Python through the folder's own virtualenv, and
    /// nothing that is not a script.
    func testScriptsInAFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jobscripts-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent(".venv/bin"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("lib"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        func write(_ name: String, executable: Bool = false) throws {
            let path = dir.appendingPathComponent(name).path
            fm.createFile(atPath: path, contents: Data("x".utf8))
            if executable {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            }
        }
        try write(".venv/bin/python", executable: true)
        try write("list_guest_users.py")
        try write("setup.sh")
        try write("run.sh", executable: true)
        try write("lib/deep.py")
        try write("requirements.txt")
        try write(".env")
        let scripts = JobScripts.suggest(in: dir.path)
        XCTAssertEqual(scripts.map(\.file), ["list_guest_users.py", "run.sh", "setup.sh"])
        XCTAssertEqual(scripts[0].argv, [".venv/bin/python", "list_guest_users.py"])
        XCTAssertEqual(scripts[1].argv, ["./run.sh"])
        XCTAssertEqual(scripts[2].argv, ["sh", "setup.sh"])
        try fm.removeItem(at: dir.appendingPathComponent(".venv"))
        XCTAssertEqual(JobScripts.suggest(in: dir.path)[0].argv, ["python3", "list_guest_users.py"], "no virtualenv, the system python")
    }

    private func approved(global: Bool = false) -> JobStatus {
        var job = JobStatus(name: "notion-guests", dir: "/x/notion", argv: [".venv/bin/python", "list_guest_users.py"], ask: "never")
        job.profile = "notion"
        job.profileGlobal = global ? true : nil
        job.secrets = [
            JobSecretStatus(name: "INTERNAL_DOMAINS", path: "notion/INTERNAL_DOMAINS"),
            JobSecretStatus(name: "OUTPUT_FILE", path: "notion/OUTPUT_FILE", shown: true)
        ]
        return job
    }

    /// Edit opens as approved, says nothing changed until something has,
    /// and names each change; approving it replaces the job, never renames.
    func testEditStartsAsApprovedAndNamesWhatChanged() {
        var draft = JobDraft(editing: approved())
        XCTAssertEqual(draft.command, ".venv/bin/python list_guest_users.py")
        XCTAssertEqual(draft.shown, ["OUTPUT_FILE"])
        XCTAssertEqual(draft.ask, .never)
        XCTAssertEqual(draft.missing, "Nothing changed yet")
        draft.shown = ["INTERNAL_DOMAINS"]
        draft.ask = .eachTime
        XCTAssertEqual(draft.changes, ["INTERNAL_DOMAINS shown", "OUTPUT_FILE hidden", "asks each time"])
        XCTAssertTrue(draft.isComplete)
        let spec = draft.spec(pathEnv: "", home: "")
        XCTAssertEqual(spec.replace, true)
        XCTAssertEqual(spec.profile, GrantProfile(name: "notion", root: "/x/notion"))
        XCTAssertEqual(draft.cleared().name, "notion-guests", "changing the profile keeps the job's name")
        XCTAssertNotNil(draft.cleared().editing)
    }

    /// A job made from ~/.jit/profiles is edited as one: no root is sent.
    func testEditKeepsAGlobalProfileGlobal() {
        var draft = JobDraft(editing: approved(global: true))
        draft.ask = .eachTime
        XCTAssertNil(draft.spec(pathEnv: "", home: "").profile?.root)
        XCTAssertNil(JobReview(job: approved(global: true)).reapproval(pathEnv: "", home: "").profile?.root)
    }
}
