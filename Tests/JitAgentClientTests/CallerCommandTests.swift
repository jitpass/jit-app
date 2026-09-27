// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class CallerCommandTests: XCTestCase {
    private func name(_ line: String) -> String? {
        CallerCommand(line)?.program
    }

    func testNamesTheProgramNotAnArgument() {
        XCTAssertEqual(name("/opt/homebrew/bin/claude --resume"), "claude")
        XCTAssertEqual(name("/usr/local/bin/node /Users/x/proj/server.js"), "node")
        XCTAssertEqual(name("python3 /Users/x/tools/fetch.py --out /tmp/a.json"), "python3")
        XCTAssertEqual(CallerCommand("/usr/local/bin/node /Users/x/proj/server.js")?.shown, "node /Users/x/proj/server.js")
        XCTAssertEqual(CallerCommand("/Users/x/.jit/bin/acme run python server.py")?.shown, "acme run python server.py")
    }

    /// A path with a space: the first space is not where the program ends.
    func testPathsWithSpaces() {
        XCTAssertEqual(name("/Applications/Acme Studio.app/Contents/MacOS/acme"), "acme")
        XCTAssertEqual(
            name("/Applications/Acme.app/Contents/Frameworks/Acme Helper.app/Contents/MacOS/Acme Helper --type=utility"),
            "Acme Helper"
        )
        let mac: Set = ["/Users/x/My Tools/bin/fetch"]
        XCTAssertEqual(CallerCommand("/Users/x/My Tools/bin/fetch --all", isExecutable: mac.contains)?.shown, "fetch --all")
    }

    /// The program is what is on disk, so a relative-path argument is never
    /// glued onto it: "node dist/server.js" names node, the interpreter that
    /// asked (review, 2026-09-27).
    func testARelativeArgumentIsNotTheProgram() {
        let mac: Set = ["/usr/local/bin/node", "/usr/bin/python3", "/bin/zsh"]
        for (line, shown) in [
            ("/usr/local/bin/node dist/server.js", "node dist/server.js"),
            ("/usr/bin/python3 scripts/fetch.py", "python3 scripts/fetch.py"),
            ("/bin/zsh ./run.sh", "zsh ./run.sh")
        ] {
            XCTAssertEqual(CallerCommand(line, isExecutable: mac.contains)?.shown, shown)
        }
        // Not on disk any more: still the first word, never the argument.
        XCTAssertEqual(CallerCommand("/gone/bin/node dist/server.js", isExecutable: { _ in false })?.program, "node")
    }

    /// An app's executable ends where its name does, not at the next dash;
    /// and a Contents/MacOS that belongs to an argument names nothing.
    func testAppBundleProgramsAndTheirArguments() {
        let mac: Set = ["/Applications/Acme.app/Contents/MacOS/acme", "/usr/bin/open"]
        XCTAssertEqual(CallerCommand("/Applications/Acme.app/Contents/MacOS/acme serve", isExecutable: mac.contains)?.shown, "acme serve")
        XCTAssertEqual(CallerCommand("/usr/bin/open /Applications/X.app/Contents/MacOS/x", isExecutable: mac.contains)?.program, "open")
        // Off disk, from the text: the bundle's own name, then the first space.
        let gone: (String) -> Bool = { _ in false }
        XCTAssertEqual(CallerCommand("/Applications/Acme.app/Contents/MacOS/acme run x.py", isExecutable: gone)?.shown, "acme run x.py")
        XCTAssertEqual(
            CallerCommand("/Applications/Acme Helper.app/Contents/MacOS/Acme Helper -x", isExecutable: gone)?.program,
            "Acme Helper"
        )
    }

    /// The real file system is asked once per line: every audit row and
    /// every AI Agents refresh names its program on the main thread, and a
    /// week of events repeats the same lines (review, 2026-09-27).
    func testTheDiskIsAskedOncePerLine() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + " tools")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exe = dir.appendingPathComponent("fetch")
        try Data("#!/bin/sh\n".utf8).write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        let line = exe.path + " dist/run.js"
        XCTAssertEqual(CallerCommand(line)?.shown, "fetch dist/run.js", "found on disk, spaces in its folder and all")
        try FileManager.default.removeItem(at: dir)
        XCTAssertEqual(CallerCommand(line)?.shown, "fetch dist/run.js", "the second answer is the remembered one")
    }

    func testEmptyIsNil() {
        XCTAssertNil(CallerCommand(""))
        XCTAssertNil(CallerCommand(nil))
    }

    /// Audit titles, the panel, Decoys and consent all name the program
    /// through it.
    func testEveryReaderUsesIt() {
        let event = SessionEvent(unixTime: 0, kind: "unlock", op: "unwrap", by: "/usr/local/bin/node /Users/x/proj/server.js")
        XCTAssertEqual(AuditReport.title(for: event), "unlocked by node /Users/x/proj/server.js")
        XCTAssertEqual(AuditReport.program("/Applications/Acme Studio.app/Contents/MacOS/acme"), "acme")
        XCTAssertEqual(
            ConsentRequest(event: SessionEvent(
                unixTime: 0,
                kind: "pending",
                // A helper in its own bundle, as Electron and Chrome lay them
                // out. Off disk, a spaced name sitting straight in another
                // bundle's MacOS cannot be told from "acme serve" by the text.
                by: "/Applications/Acme.app/Contents/Frameworks/Acme Helper.app/Contents/MacOS/Acme Helper --type=x",
                consentID: "c1"
            ))?.program,
            "Acme Helper"
        )
    }

    /// Two programs that first read a file in the same second, for the same
    /// reason, are two rows with two ids.
    func testDecoyReadsOfTwoReadersInOneSecondHaveTwoIds() {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let first = DecoyReport.Read(at: at, files: ["a"], reads: 1, reader: "node", real: false, why: "locked")
        let second = DecoyReport.Read(at: at, files: ["a"], reads: 1, reader: "python3", real: false, why: "locked")
        XCTAssertNotEqual(first.id, second.id)
    }
}
