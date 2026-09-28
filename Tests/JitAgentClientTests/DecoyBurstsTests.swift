// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// An editor indexing a folder opened one protected file 1,712 times in two
/// minutes; the menu said "1733 reads today" in amber for a day. Bursts
/// and programs, not opens, and a program can be marked expected.
final class DecoyBurstsTests: XCTestCase {
    private let editor = "/Applications/My Editor.app/Contents/MacOS/Editor"
    private let t0: Int64 = 1_790_000_000

    private func read(_ at: Int64, _ file: String, by: String, count: Int = 1, expected: Bool? = nil) -> SessionEvent {
        SessionEvent(unixTime: at, kind: "serve", op: "decoy", by: by, labels: [file], count: count, expected: expected)
    }

    func testReadsCloseTogetherAreOneBurstAndAPauseStartsAnother() {
        let events = [
            read(t0, "~/work/billing/.env", by: editor + " --type=indexer", count: 1000),
            read(t0 + 60, "~/work/billing/.env", by: editor + " --type=indexer", count: 712),
            read(t0 + 60 + 301, "~/work/billing/.env", by: editor + " --type=indexer", count: 3),
            read(t0 + 90, "~/work/reports/.env", by: "/usr/bin/python3 sync.py", count: 7)
        ]
        let rows = DecoyBurst.make(events, since: nil, expected: nil)
        // The editor came back after a pause: two bursts, one row for it and
        // its file, not a row each (a server started now and then made seven).
        XCTAssertEqual(rows.map(\.reads).sorted(), [7, 1715])
        let editorRow = rows.first { $0.reads == 1715 }
        XCTAssertEqual(editorRow?.bursts, 2)
        XCTAssertNil(editorRow?.span, "a row of several bursts has no single span")
        XCTAssertEqual(DecoyBurst.unexpectedPrograms(rows), 2, "one editor, one script: programs, not bursts")

        let one = DecoyBurst.make(Array(events.prefix(2)), since: nil, expected: nil)
        XCTAssertEqual(one.first?.span, 60, "one burst keeps its span")
    }

    /// A read with no reader on record is said, not counted as a program:
    /// "4 programs" counted it as a fifth.
    func testAnUntracedReadIsNotAProgram() {
        let rows = DecoyBurst.make([
            read(t0, "~/work/billing/.env", by: editor, count: 5),
            SessionEvent(unixTime: t0 + 10, kind: "serve", op: "decoy", labels: ["~/work/reports/.env"])
        ], since: nil, expected: nil)
        XCTAssertEqual(DecoyBurst.unexpectedPrograms(rows), 1)
        XCTAssertTrue(DecoyBurst.untraced(rows))
        XCTAssertEqual(PanelValue.decoys(files: 3, broken: 0, programs: 0, untraced: true), .init("unknown reader", .amber))
    }

    /// A decoy read's `by` is the executable path alone, and a path may hold
    /// spaces: the program is all of it.
    func testTheProgramIsTheWholeExecutablePath() {
        let path = "/Applications/Some Editor.app/Contents/MacOS/Some Editor"
        XCTAssertEqual(ExpectedReaders.program(of: path), path)
    }

    func testJitsGrantWordingReadsPlainly() {
        let event = SessionEvent(unixTime: t0, kind: "serve", op: "decoy", by: "/usr/bin/uv",
                                 cause: "no jit run grant or consent approval covered the reader", labels: ["~/work/tickets/.env"])
        XCTAssertEqual(DecoyReport.reason(event), "no grant covers it")
    }

    func testAnExpectedReaderGoesLastAndStopsCounting() {
        let events = [
            read(t0, "~/work/billing/.env", by: editor, count: 1712, expected: true),
            read(t0 + 10, "~/work/reports/.env", by: editor, count: 5),
            read(t0 + 20, "~/work/billing/.env", by: "/usr/bin/python3 sync.py", count: 7)
        ]
        let bursts = DecoyBurst.make(events, since: nil, expected: nil)
        XCTAssertEqual(bursts.last?.reads, 1712)
        XCTAssertTrue(bursts.last?.expected ?? false)
        XCTAssertEqual(DecoyBurst.unexpectedPrograms(bursts), 2, "the editor's other file still counts")

        let onlyExpected = DecoyBurst.make([events[0]], since: nil, expected: nil)
        XCTAssertEqual(DecoyBurst.unexpectedPrograms(onlyExpected), 0)
        XCTAssertEqual(PanelValue.decoys(files: 6, broken: 0, programs: 0), .init("6 files"))
    }

    /// A live event jit has not labelled yet is matched against the list,
    /// by the executable whose path holds a space, and by file scope.
    func testTheListCoversByProgramAndFile() {
        let list = ExpectedReaders(expected: [ExpectedReader(program: editor, file: "~/work/billing/.env")])
        XCTAssertTrue(list.covers(by: editor + " --type=indexer", label: "~/work/billing/.env"))
        XCTAssertFalse(list.covers(by: editor, label: "~/work/reports/.env"))
        XCTAssertFalse(list.covers(by: editor + "Helper", label: "~/work/billing/.env"))
        let everywhere = ExpectedReaders(expected: [ExpectedReader(program: editor)])
        XCTAssertTrue(everywhere.covers(by: editor, label: "~/work/reports/.env"))
        let bursts = DecoyBurst.make([read(t0, "~/work/billing/.env", by: editor)], since: nil, expected: list)
        XCTAssertTrue(bursts[0].expected)
        XCTAssertEqual(ExpectedReaders.program(of: editor + " --x", known: list.expected), editor)
    }

    func testTheListDecodes() throws {
        let json = #"{"expected":[{"program":"/usr/bin/python3","file":"~/work/billing/.env","since_unix":1790000000},"#
            + #"{"program":"/opt/tools/backup"}]}"#
        let list = try JSONDecoder().decode(ExpectedReaders.self, from: Data(json.utf8))
        XCTAssertEqual(list.expected.map(\.file), ["~/work/billing/.env", nil])
    }
}
