// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Decoys counted by program and burst, and expected readers.
extension Format {
    /// "2 programs read decoys in the last 24 hours · 1 expected".
    static func decoysProgramsLine(_ bursts: [DecoyBurst], allWhileLocked: Bool) -> String {
        var text = decoysProgramsTitle(DecoyBurst.unexpectedPrograms(bursts), untraced: DecoyBurst.untraced(bursts))
        if allWhileLocked {
            text += ", all while the vault was locked"
        }
        let expected = Set(bursts.filter(\.expected).map { $0.by ?? "" }).count
        if expected > 0 {
            text += " · \(expected) expected"
        }
        return text
    }

    /// "4 programs, and a reader jit couldn't trace, read decoys…": a read
    /// with no reader on record is said, not counted as a program.
    static func decoysProgramsTitle(_ programs: Int, untraced: Bool = false) -> String {
        let who = programs == 1 ? "1 program" : "\(programs) programs"
        switch (programs, untraced) {
        case (0, false): return "No unexpected decoy reads in the last 24 hours"
        case (0, true): return "A reader jit couldn't trace read decoys in the last 24 hours"
        case (_, true): return who + ", and a reader jit couldn't trace, read decoys in the last 24 hours"
        default: return who + " read decoys in the last 24 hours"
        }
    }

    /// "Read it 1,712 times in 2 minutes · 15 hours ago · no grant covers it";
    /// for a reader that came back several times, "Read it 13 times · last
    /// 2 hours ago · …".
    static func decoyBurstFact(_ burst: DecoyBurst, cannotExpect: Bool = false) -> String {
        var first = burst.reads == 1 ? "Read it once" : "Read it \(burst.reads.formatted(.number)) times"
        if let span = burst.span {
            first += " in " + spanWords(span)
        }
        let when = burst.bursts > 1 ? "last " + ScanWording.when(burst.last) : ScanWording.when(burst.last)
        return ([first, when, burst.why] + (cannotExpect ? [decoyCannotExpect] : [])).joined(separator: " · ")
    }

    static func spanWords(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return minutes <= 1 ? "a minute" : "\(minutes) minutes"
        }
        let hours = Int((seconds / 3600).rounded())
        return hours == 1 ? "an hour" : "\(hours) hours"
    }

    static let decoysReadsExpectNote = "Each got fake values. Mark a program expected when its reads are routine, "
        + "such as an editor indexing a folder: they stay in the audit and stop raising Decoys."

    static func expectedReaderName(_ reader: ExpectedReader) -> String {
        CallerCommand(reader.program)?.program ?? reader.program
    }

    static func expectedReaderFact(_ reader: ExpectedReader) -> String {
        var parts = [reader.file.map(decoyFileName) ?? "every protected file"]
        if let since = reader.sinceUnix {
            parts.append("marked " + ScanWording.when(Date(timeIntervalSince1970: TimeInterval(since))))
        }
        return parts.joined(separator: " · ")
    }

    static func expectQuestion(_ burst: DecoyBurst) -> String {
        "Treat \(burst.reader ?? "this program")'s reads as expected?"
    }

    static let expectMessage = "It still gets decoys, and every read stays in the audit. "
        + "Its reads stop turning Decoys amber and stop notifying you. Any other program still does."

    static func expectOneFile(_ burst: DecoyBurst) -> String {
        "Only " + decoyFileName(burst.file)
    }

    static let expectEveryFile = "Every protected file"
    static let expectOneFileHint = "Its reads of other files still count."
    static let expectEveryFileHint = "For a program that opens whole folders, like an editor or a backup tool."

    static func decoyExpectedBanner(_ reader: ExpectedReader, remove: Bool) -> String {
        let name = expectedReaderName(reader)
        let what = reader.file.map(decoyFileName) ?? "protected files"
        return remove ? "\(name)'s reads of \(what) count again" : "\(name)'s reads of \(what) are expected"
    }

    static func decoyExpectFailed(remove: Bool, _ why: String) -> String {
        (remove ? "Nothing changed: " : "Not marked expected: ") + why
    }

    /// Why a shell or an interpreter's row has no Expected…: it runs any
    /// script, so the mark would silence every one (jit refuses it too).
    static let decoyCannotExpect = "runs any script, so it can't be marked expected"
}
