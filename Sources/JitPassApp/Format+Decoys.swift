// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Every sentence the Decoys window says.
extension Format {
    static func decoysHeadline(_ report: DecoyReport, open: Int) -> String {
        guard !report.files.isEmpty || open > 0 else {
            return "No file is protected yet"
        }
        return count(report.files.count, "file") + " protected · " + (open == 0 ? "0 in the open" : count(open, "file") + " in the open")
    }

    static func decoysSubline(scanAt: Date?, deep: Bool) -> String {
        var text = "A protected file keeps its names, not its values: "
            + "a program gets the real values only through jit, and a decoy otherwise."
        if let scanAt {
            text += " " + (deep ? "Deep scan " : "Scan ") + ScanWording.when(scanAt) + "; reads from the audit, live."
        }
        return text
    }

    static func decoysOpenLine(_ open: Int) -> String {
        (open == 1 ? "1 file still holds" : "\(open) files still hold") + " plaintext secrets"
    }

    static func decoysReadsLine(_ report: DecoyReport) -> String {
        var text = count(report.decoyReads, "decoy read") + " this week"
        if report.allWhileLocked {
            text += ", all while the vault was locked"
        }
        return text
    }

    static func decoysFooter(_ report: DecoyReport, open: Int) -> String {
        var parts = [count(report.files.count, "file")]
        if open > 0 {
            parts.append(count(open, "file") + " in the open")
        }
        if report.secrets > 0 {
            parts.append(count(report.secrets, "secret") + " from them in the vault")
        }
        parts.append(count(report.decoyReads, "decoy read") + " this week")
        return parts.joined(separator: " · ")
    }

    /// "hibob/.env": the folder that tells the files apart, then the name.
    static func decoyFileName(_ path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count >= 2 else {
            return path
        }
        return parts.suffix(2).joined(separator: "/")
    }

    /// The folder above that: "~/Security-Ops/custom_scripts".
    static func decoyFolder(_ path: String) -> String {
        home(((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent)
    }

    static func decoyFileFact(_ file: DecoyReport.File) -> String {
        var parts =
            [file.secrets == 0 ? "no vault entry names this file as its origin" : count(file.secrets, "secret") + " from it in the vault"]
        if let missing = file.missing {
            parts.append(missing + " is not in the vault")
            if let at = file.missingAt {
                parts.append("a run got nothing " + ScanWording.when(at))
            }
            return parts.joined(separator: " · ")
        }
        parts.append(count(file.decoyReads, "decoy read") + " this week")
        if let read = file.lastRead {
            parts.append("last opened " + ScanWording.when(read))
        }
        if let real = file.lastRealRead {
            parts.append("last real read " + ScanWording.when(real))
        } else {
            parts.append("never read for real")
        }
        return parts.joined(separator: " · ")
    }

    static func decoyReadFiles(_ read: DecoyReport.Read) -> String {
        if read.files.count > 2 {
            return count(read.files.count, "file") + " at once"
        }
        return read.files.map { decoyFileName($0) }.joined(separator: " · ")
    }

    static func decoyReadFact(_ read: DecoyReport.Read) -> String {
        var parts = [read.reader.map { "read by " + $0 } ?? "reader not recorded", read.why]
        if read.reads > 1 {
            parts.append(count(read.reads, "read"))
        }
        return parts.joined(separator: " · ")
    }

    static let decoysOpenNote = "The same rows Findings shows, with the same verb: "
        + "jit moves the values into the vault and a decoy takes the file's place."
    static let decoysProtectedNote = "Each keeps the names, not the values. "
        + "A program reading it outside a run or a grant gets the decoy, and the read is logged."
    static let decoysReadsNote = "Who opened a protected file and what they got. "
        + "A decoy read is jit working; the reason says whether it was the lock, a missing grant, or a stranger."
    static let decoysEmptyMessage = "When jit protects a .env or a credentials file, the file stays where it is and serves decoys: "
        + "a program gets the real values only through jit. Findings offers the files it can protect."
}
