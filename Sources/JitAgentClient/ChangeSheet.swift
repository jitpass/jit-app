// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A note's mark on the change sheet: a promise kept (a tick), something
/// left for later (amber), or a failure (a cross).
public enum ChangeMark: Equatable, Sendable {
    case done, left, failed
}

/// What a Redact or a Protect changed, as the sheet behind the banner's
/// "What Changed…" shows it: the result in one line, what was not touched,
/// one row per file, what the action promised, and what it could not do.
/// Built from the JSON jit already returns (`RedactReport`,
/// `MigrateReport`), so no row is parsed out of jit's text. jit's text
/// stays in `report`, one disclosure away: a success is not a terminal.
public struct ChangeSheet: Equatable, Sendable {
    /// A file the action changed: the path, and one clause about it.
    public struct File: Equatable, Sendable {
        public var path: String
        public var fact: String
    }

    /// A line under the files: a promise kept (a tick), something left for
    /// later (amber), or a failure with jit's words under it (a cross).
    public struct Note: Equatable, Sendable {
        public var mark: ChangeMark
        public var name: String
        public var fact: String
        /// jit's own words, for a failure only: the one case they are the
        /// diagnosis.
        public var verbatim: String?
    }

    public var title: String
    public var sentence: String
    public var files: [File]
    public var notes: [Note]
    /// The files a Protect applied to, for the sheet's Undo; empty after a
    /// Redact, which has none.
    public var undo: [String]
    /// jit's text report, behind "Show jit's report".
    public var report: String

    /// Past this many files the rest fold into one row until asked for.
    public static let shown = 3

    /// The sheet's failures first: a cross leads, then what did change.
    public var failed: Bool {
        notes.contains { $0.mark == .failed }
    }
}

public extension ChangeSheet {
    /// Whether a banner's "What Changed…" has anything the banner does not
    /// already say: this sheet's rows, or jit's words where they are more
    /// than the banner's sentence. A result whose words are its sentence
    /// (Connect, Disconnect) would only say it again, so it has no button.
    static func addsTo(banner title: String, text: String, sheet: ChangeSheet?) -> Bool {
        if sheet != nil {
            return true
        }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !words.isEmpty && words != title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// After a Redact: every file is an agent's cache, so the sentence says
    /// the reader's own files were not touched.
    static func redact(_ report: RedactReport) -> ChangeSheet {
        let tokens = report.tokensRedacted
        let files = report.caches.removed.count
        let title = tokens > 0
            ? "Redacted \(count(tokens, "token")) in \(count(files, "file"))"
            : report.errors.isEmpty ? "Nothing to redact" : "Redact did not finish"
        let places = ScanWording.agentPlaces(report.caches.removed.map { (agent: $0.agent, area: $0.area) })
        let sentence = places.isEmpty
            ? "Your own files were not touched."
            : "All in " + places.joined(separator: " and ") + ". Your own files were not touched."
        var notes: [Note] = []
        if !report.errors.isEmpty {
            notes.append(Note(
                mark: .failed,
                name: "Redact did not finish",
                fact: tokens > 0 ? "What changed below stays changed." : "Nothing was changed.",
                verbatim: report.errors.joined(separator: "\n")
            ))
        }
        if tokens > 0 {
            notes.append(Note(
                mark: .done,
                name: "Each token is now a marker that names it",
                fact: "<jit:redacted:VENDOR>, and the rest of the line is as it was"
            ))
            notes.append(Note(
                mark: .done,
                name: "No backup was kept",
                fact: "A copy would be one more place the token lives. The marker is the record."
            ))
        }
        notes += leftNotes(report.caches.left)
        return ChangeSheet(
            title: title,
            sentence: sentence,
            files: report.caches.removed.map {
                File(path: $0.path, fact: "\($0.agent) · \($0.area) · " + count($0.copies ?? 0, "token"))
            },
            notes: notes,
            undo: [],
            report: report.report
        )
    }

    /// After a Protect: the files it moved secrets out of, the secrets now
    /// in the vault, the cached copies removed and left. jit reports the
    /// vaulted names for the run, not per file, so the names are one line
    /// rather than a guess on each file's row.
    static func protect(_ reports: [MigrateReport], wrapped: [String] = [], report text: String) -> ChangeSheet {
        let applied = reports.filter(\.applied)
        let targets = applied.flatMap(\.targets)
        let vaulted = reports.flatMap(\.vaulted)
        let errors = reports.flatMap(\.errors)
        var title = targets.isEmpty
            ? (errors.isEmpty ? "Nothing to protect" : "Protect did not finish")
            : "Protected " + count(targets.count, "file")
        if !vaulted.isEmpty {
            title += " · " + (vaulted.count == 1 ? "1 secret is" : "\(vaulted.count) secrets are") + " in the vault"
        }
        var notes: [Note] = []
        if !errors.isEmpty {
            notes.append(Note(
                mark: .failed,
                name: "Protect did not finish",
                fact: targets.isEmpty ? "Nothing was changed." : "What changed below stays changed, and Undo still restores it.",
                verbatim: errors.joined(separator: "\n")
            ))
        }
        if !vaulted.isEmpty {
            notes.append(Note(mark: .done, name: "In the vault", fact: vaulted.joined(separator: ", ")))
        }
        let removed = reports.flatMap(\.caches.removed)
        let copies = removed.reduce(0) { $0 + ($1.copies ?? 0) }
        if copies > 0 {
            notes.append(Note(
                mark: .done,
                name: count(copies, "cached copy", plural: "cached copies") + " removed",
                fact: ScanWording.agentPlaces(removed.map { (agent: $0.agent, area: $0.area) }).joined(separator: ", ")
            ))
        }
        for tool in wrapped {
            notes.append(Note(mark: .done, name: "Wrapped " + tool, fact: "It gets its key from the vault when it runs."))
        }
        notes += leftNotes(reports.flatMap(\.caches.left))
        return ChangeSheet(
            title: title,
            sentence: targets.isEmpty
                ? "No file was changed."
                : "Each file keeps its place; a decoy stands where each value was. Undo puts every file back from its backup.",
            files: targets.map { File(path: $0, fact: "Backed up, then its secrets moved to the vault") },
            notes: notes,
            undo: targets,
            report: text
        )
    }

    /// Cache files the action could not rewrite, grouped by why: an agent
    /// still writing one, a binary store, or jit's own reason.
    private static func leftNotes(_ left: [MigrateReport.CacheFile]) -> [Note] {
        guard !left.isEmpty else {
            return []
        }
        let places = ScanWording.agentPlaces(left.map { (agent: $0.agent, area: $0.area) }).joined(separator: " and ")
        let name = count(left.count, "file") + " left in " + places
        let live = left.filter { $0.kind == "live" }
        let fact = if let first = live.first {
            "\(first.agent) is writing " + (live.count == 1 ? "it" : "them") + ". The next scan tries again."
        } else if left.allSatisfy({ $0.kind == "binary" }) {
            "A binary store jit won't rewrite."
        } else {
            left.compactMap(\.reason).first ?? "jit left it as it was."
        }
        return [Note(mark: .left, name: name, fact: fact)]
    }

    private static func count(_ n: Int, _ one: String, plural: String? = nil) -> String {
        "\(n) " + (n == 1 ? one : plural ?? one + "s")
    }
}
