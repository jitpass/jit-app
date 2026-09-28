// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Decoys counted by program and burst, and expected readers.
extension Format {
    /// The header's line, "2 programs read decoys in 24 hours": short, so it
    /// stays one line beside the mark and its "see them". The expected
    /// count is the Reads card's to say.
    static func decoysProgramsLine(_ bursts: [DecoyBurst], allWhileLocked: Bool) -> String {
        let untraced = DecoyBurst.untraced(bursts)
        // With an untraced reader the sentence is long enough to wrap its
        // "see them": the window is dropped there, the Reads title and the
        // footer still say it.
        var text = decoysProgramsTitle(DecoyBurst.unexpectedPrograms(bursts), untraced: untraced)
            .replacingOccurrences(of: " in the last 24 hours", with: untraced ? "" : " in 24 hours")
        if allWhileLocked {
            text += ", all while the vault was locked"
        }
        return text
    }

    /// "4 programs and an untraced reader read decoys…": a read with no
    /// reader on record is said, not counted as a program, in few enough
    /// words to keep the header's line to one.
    static func decoysProgramsTitle(_ programs: Int, untraced: Bool = false) -> String {
        let who = programs == 1 ? "1 program" : "\(programs) programs"
        switch (programs, untraced) {
        case (0, false): return "No unexpected decoy reads in the last 24 hours"
        case (0, true): return "An untraced reader read decoys in the last 24 hours"
        case (_, true): return who + " and an untraced reader read decoys in the last 24 hours"
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

    /// The Reads note when no row can be marked: only what is true.
    static let decoysReadsPlainNote = "Each got fake values."

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
