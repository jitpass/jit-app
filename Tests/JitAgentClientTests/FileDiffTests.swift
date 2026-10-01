// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class FileDiffTests: XCTestCase {
    /// Two hunks, the second ending without a newline: git's own shape for
    /// `git diff --no-color HEAD -- config.yaml`.
    private let twoHunks = """
    diff --git a/config.yaml b/config.yaml
    index 3b18e51..a1f3c2d 100644
    --- a/config.yaml
    +++ b/config.yaml
    @@ -12,4 +12,5 @@ service:
       region: eu-west-1
    -  api_key: <jit:redacted:STRIPE>
    +  api_key: ${STRIPE_KEY}
    +  timeout: 30
       retries: 3
    @@ -40,2 +41,2 @@ logging:
       level: info
    -  file: /var/log/app.log
    \\ No newline at end of file
    +  file: /var/log/demo-app.log
    \\ No newline at end of file

    """

    func testDiffIsLinesWithTheirNumbersAndNoGitHeaders() {
        let diff = FileDiff.make(file: "/Users/dana/demo/config.yaml", output: twoHunks)
        XCTAssertEqual(diff.outcome, .changed)
        XCTAssertEqual(diff.title, "config.yaml changed since git's last commit")
        XCTAssertEqual(diff.sentence, "3 lines added, 2 removed.")
        XCTAssertEqual(diff.added, 3)
        XCTAssertEqual(diff.removed, 2)
        XCTAssertFalse(diff.lines.contains { $0.text.hasPrefix("diff --git") || $0.text.hasPrefix("index ") || $0.text.hasPrefix("+++") })

        let drawn = diff.lines.map { "\($0.kind) \($0.number.map(String.init) ?? "-") \($0.text)" }
        XCTAssertEqual(drawn, [
            "hunk - lines 12–16",
            "context 12   region: eu-west-1",
            "removed 13   api_key: <jit:redacted:STRIPE>",
            "added 13   api_key: ${STRIPE_KEY}",
            "added 14   timeout: 30",
            "context 15   retries: 3",
            "hunk - lines 41–42",
            "context 41   level: info",
            "removed 41   file: /var/log/app.log",
            "note - No newline at end of file",
            "added 42   file: /var/log/demo-app.log",
            "note - No newline at end of file"
        ])
        XCTAssertEqual(diff.lines.map(\.id), Array(0 ..< diff.lines.count), "ids are unique and in order")
    }

    /// git answers with nothing when the file was rewritten as it was: the
    /// sentence says so, and there is no box to draw.
    func testNoDifferenceIsASentenceOnly() {
        let diff = FileDiff.make(file: "notes/plan.md", output: "")
        XCTAssertEqual(diff.outcome, .unchanged)
        XCTAssertEqual(diff.title, "plan.md is the same as git's last commit")
        XCTAssertEqual(diff.sentence, "It was rewritten with the same content.")
        XCTAssertTrue(diff.lines.isEmpty)
    }

    func testGitFailingIsSaid() {
        let diff = FileDiff.make(file: "a/b.txt", output: nil)
        XCTAssertEqual(diff.outcome, .failed)
        XCTAssertEqual(diff.title, "Couldn't show the changes to b.txt")
        XCTAssertTrue(diff.lines.isEmpty)
    }

    func testCountsLeftOutAreOneAndARemovalNamesWhereItWas() {
        let diff = FileDiff.make(file: "x.env", output: "@@ -3 +3 @@\n-OLD=1\n+NEW=1\n@@ -9,2 +9,0 @@\n-A=1\n-B=2\n")
        XCTAssertEqual(diff.lines.filter { $0.kind == .hunk }.map(\.text), ["line 3", "lines 9–10, removed"])
        XCTAssertEqual(diff.lines.filter { $0.kind == .removed }.map(\.number), [3, 9, 10])
        XCTAssertEqual(diff.sentence, "1 line added, 3 removed.")
    }

    func testSentenceForOneSide() {
        XCTAssertEqual(FileDiff.sentence(added: 0, removed: 1), "1 line removed.")
        XCTAssertEqual(FileDiff.sentence(added: 4, removed: 0), "4 lines added.")
    }

    /// An empty context line (a tool stripped its trailing space) stays a
    /// context line and keeps the numbering right.
    func testEmptyContextLineKeepsNumbering() {
        let diff = FileDiff.make(file: "f", output: "@@ -1,3 +1,3 @@\n a\n\n-b\n+c\n")
        XCTAssertEqual(diff.lines.map(\.number), [nil, 1, 2, 3, 3])
    }

    func testALongDiffIsCappedButCountedWhole() {
        let body = (1 ... 30).map { "+line \($0)" }.joined(separator: "\n")
        let diff = FileDiff.make(file: "big.txt", output: "@@ -0,0 +1,30 @@\n" + body + "\n", limit: 10)
        XCTAssertEqual(diff.lines.count, 10)
        XCTAssertTrue(diff.truncated)
        XCTAssertEqual(diff.added, 30)
        XCTAssertEqual(diff.sentence, "30 lines added. Only the first 10 lines are shown.")
    }
}
