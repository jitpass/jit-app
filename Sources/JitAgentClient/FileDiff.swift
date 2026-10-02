// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One file's change since git's last commit, as the AI job review's
/// Show Changes draws it: a title, one sentence, and the diff as lines with
/// their line numbers. Parsed from `git diff --no-color HEAD -- <file>`, so
/// the sheet never shows git's headers (`diff --git`, `index`, `---`,
/// `+++`) or its `@@ -12,4 +12,5 @@` syntax; a hunk becomes a quiet
/// "lines 12–16" label. The lines stay code: monospaced, and only the
/// sign is replaced by colour.
public struct FileDiff: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The start of a hunk; `text` is its "lines a–b" label.
        case hunk
        case context, added, removed
        /// git's "\ No newline at end of file", said as a quiet note.
        case note
    }

    /// One drawn line. `number` is the line's number in the file it is
    /// from: the old file for a removed line, the new file for the rest.
    /// Nil for a hunk label and a note.
    public struct Line: Equatable, Sendable, Identifiable {
        public var id: Int
        public var kind: Kind
        public var number: Int?
        public var text: String
    }

    public enum Outcome: Equatable, Sendable {
        /// git showed changes.
        case changed
        /// git answered with nothing: the file was rewritten as it was.
        case unchanged
        /// git could not answer for this file.
        case failed
    }

    public var outcome: Outcome
    public var title: String
    public var sentence: String
    public var lines: [Line]
    public var added: Int
    public var removed: Int
    /// The diff ran past `limit` lines, or past `budget` characters, and
    /// the rest is not drawn.
    public var truncated: Bool
    /// git named the file but drew no lines for it: a binary file, or a
    /// change of its mode alone. Said in the sentence, never as unchanged.
    public var binary = false
    public var mode: Mode?

    /// A file's mode before and after, as git prints it ("100644").
    public struct Mode: Equatable, Sendable {
        public var old: String
        public var new: String
    }

    /// git printed its header for the file (`diff --git`), so something
    /// changed even when no line can be drawn.
    var sawHeader = false

    /// The most lines drawn: a review needs the change, not a megabyte
    /// of it.
    public static let limit = 2000
    /// The most characters drawn on one line (a minified bundle is one
    /// line), and in the whole diff: a review sheet must not lay out
    /// megabytes of text on the main thread.
    public static let lineBudget = 400
    public static let budget = 100_000

    /// `output` is git's stdout, nil when git did not exit 0. `file` is
    /// the path git was asked about; only its name is shown.
    public static func make(file: String, output: String?, limit: Int = limit) -> FileDiff {
        let name = (file as NSString).lastPathComponent
        guard let output else {
            return FileDiff(
                outcome: .failed, title: "Couldn't show the changes to \(name)",
                sentence: "git could not compare this file with its last commit.",
                lines: [], added: 0, removed: 0, truncated: false
            )
        }
        var diff = parse(output, limit: limit)
        if diff.lines.isEmpty {
            // Only an empty answer means unchanged. A header with no hunk
            // is a change git can't draw: a binary file (an AI job that
            // rewrote a key file), or new permissions.
            guard diff.sawHeader || diff.binary || diff.mode != nil else {
                diff.outcome = .unchanged
                diff.title = "\(name) is the same as git's last commit"
                diff.sentence = "It was rewritten with the same content."
                return diff
            }
            diff.title = "\(name) changed since git's last commit"
            if diff.binary {
                diff.sentence = "It's a binary file, so the change can't be drawn. Open it to check what changed."
            } else if let mode = diff.mode {
                diff.sentence = "Only its permissions changed: \(mode.old) to \(mode.new)."
            } else {
                diff.sentence = "git reports a change it can't draw. Open the file to check it."
            }
            return diff
        }
        diff.title = "\(name) changed since git's last commit"
        diff.sentence = sentence(added: diff.added, removed: diff.removed)
        if diff.truncated {
            diff.sentence += " Only the first \(limit) lines are shown."
        }
        return diff
    }

    /// The lines of a unified diff, with git's file headers dropped and
    /// each hunk's numbers carried onto its lines. Counts cover the whole
    /// diff even past `limit`.
    static func parse(_ text: String, limit: Int = limit) -> FileDiff {
        var diff = FileDiff(outcome: .changed, title: "", sentence: "", lines: [], added: 0, removed: 0, truncated: false)
        var old = 0, new = 0
        var inHunk = false
        var drawn = 0
        var oldMode: String?
        func append(_ kind: Kind, _ number: Int?, _ text: String) {
            diff.draw(kind, number, text, limit: limit, drawn: &drawn)
        }
        var rows = text.components(separatedBy: "\n")
        if rows.last == "" {
            rows.removeLast()
        }
        for row in rows {
            if row.hasPrefix("@@"), let hunk = Hunk(row) {
                inHunk = true
                old = hunk.oldStart
                new = hunk.newStart
                append(.hunk, nil, hunk.label)
                continue
            }
            if row.hasPrefix("diff --git ") {
                inHunk = false
                diff.sawHeader = true
                continue
            }
            // Before the first hunk, and between files, everything is
            // git's header: diff --git, index, ---/+++, mode lines. Two of
            // them are the change itself when no hunk follows.
            guard inHunk else {
                header(row, into: &diff, oldMode: &oldMode)
                continue
            }
            switch row.first {
            case "+":
                diff.added += 1
                append(.added, new, String(row.dropFirst()))
                new += 1
            case "-":
                diff.removed += 1
                append(.removed, old, String(row.dropFirst()))
                old += 1
            case "\\":
                append(.note, nil, "No newline at end of file")
            default:
                // " text", or "" where a tool stripped an empty context
                // line's trailing space.
                append(.context, new, row.isEmpty ? "" : String(row.dropFirst()))
                old += 1
                new += 1
            }
        }
        return diff
    }

    /// One line onto the sheet, unless `limit` lines or `budget`
    /// characters are already drawn; a line past `lineBudget` is cut.
    private mutating func draw(_ kind: Kind, _ number: Int?, _ text: String, limit: Int, drawn: inout Int) {
        guard lines.count < limit, drawn < Self.budget else {
            truncated = true
            return
        }
        let shown = text.count > Self.lineBudget ? String(text.prefix(Self.lineBudget)) + "…" : text
        drawn += shown.count
        lines.append(Line(id: lines.count, kind: kind, number: number, text: shown))
    }

    /// A header line that is the change itself when no hunk follows: a
    /// binary file, or a mode changed alone.
    private static func header(_ row: String, into diff: inout FileDiff, oldMode: inout String?) {
        if row.hasPrefix("Binary files "), row.hasSuffix(" differ") {
            diff.binary = true
        } else if row.hasPrefix("old mode ") {
            oldMode = String(row.dropFirst("old mode ".count))
        } else if row.hasPrefix("new mode "), let was = oldMode {
            diff.mode = Mode(old: was, new: String(row.dropFirst("new mode ".count)))
        }
    }

    static func sentence(added: Int, removed: Int) -> String {
        let lines = { (n: Int) in n == 1 ? "1 line" : "\(n) lines" }
        switch (added, removed) {
        case (0, _): return "\(lines(removed)) removed."
        case (_, 0): return "\(lines(added)) added."
        default: return "\(lines(added)) added, \(removed) removed."
        }
    }

    /// `@@ -oldStart[,oldCount] +newStart[,newCount] @@ …`. A count left
    /// out is 1, as in git.
    struct Hunk {
        var oldStart: Int, oldCount: Int, newStart: Int, newCount: Int

        init?(_ row: String) {
            let parts = row.split(separator: " ")
            guard parts.count >= 3, parts[1].hasPrefix("-"), parts[2].hasPrefix("+"),
                  let old = Self.range(parts[1].dropFirst()), let new = Self.range(parts[2].dropFirst())
            else {
                return nil
            }
            (oldStart, oldCount, newStart, newCount) = (old.start, old.count, new.start, new.count)
        }

        private static func range(_ text: Substring) -> (start: Int, count: Int)? {
            let pieces = text.split(separator: ",", omittingEmptySubsequences: false)
            guard let start = Int(pieces[0]) else {
                return nil
            }
            guard pieces.count > 1 else {
                return (start, 1)
            }
            guard let count = Int(pieces[1]) else {
                return nil
            }
            return (start, count)
        }

        /// The new file's lines the hunk covers; a hunk that only removes
        /// lines covers none there, so it names where they were.
        var label: String {
            if newCount == 0 {
                return oldCount == 1 ? "line \(oldStart), removed" : "lines \(oldStart)–\(oldStart + oldCount - 1), removed"
            }
            return newCount == 1 ? "line \(newStart)" : "lines \(newStart)–\(newStart + newCount - 1)"
        }
    }
}
