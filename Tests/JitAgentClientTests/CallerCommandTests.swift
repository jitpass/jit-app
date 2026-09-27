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
        XCTAssertEqual(name("/Users/x/My Tools/bin/fetch --all"), "fetch")
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
                by: "/Applications/Acme.app/Contents/MacOS/Acme Helper --type=x",
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
