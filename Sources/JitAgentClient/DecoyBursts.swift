// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A program the user said reads protected files routinely (`jit decoys
/// expect`): one file, or every protected file when `file` is nil. It
/// still gets decoys; its reads only stop counting as news.
public struct ExpectedReader: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// The reader's executable, as the audit's `by` names it.
    public var program: String
    /// The file, as the audit labels it ("~/work/app/.env"); nil for every
    /// protected file.
    public var file: String?
    public var sinceUnix: Int64?

    public var id: String {
        program + "\n" + (file ?? "")
    }

    enum CodingKeys: String, CodingKey {
        case program, file
        case sinceUnix = "since_unix"
    }

    public init(program: String, file: String? = nil, sinceUnix: Int64? = nil) {
        self.program = program
        self.file = file
        self.sinceUnix = sinceUnix
    }

    /// Whether a read by `by` of `label` is this reader's. `by` may carry
    /// arguments after the executable, whose path may itself hold spaces.
    public func covers(by: String?, label: String) -> Bool {
        guard let by, by == program || by.hasPrefix(program + " ") else {
            return false
        }
        return file == nil || file == label
    }
}

/// `jit decoys expected|expect|unexpect --format json`.
public struct ExpectedReaders: Codable, Sendable, Equatable {
    public var expected: [ExpectedReader]

    public init(expected: [ExpectedReader]) {
        self.expected = expected
    }

    public func covers(by: String?, label: String) -> Bool {
        expected.contains { $0.covers(by: by, label: label) }
    }

    /// Programs that run whatever they are given: marking one expected
    /// would silence every script it runs, `python3 exfil.py` included.
    /// jit refuses `jit decoys expect` for these (by executable basename,
    /// case-insensitive, a version suffix allowed); the app mirrors the
    /// set so it never offers the mark.
    static let runsAnything: Set<String> = [
        "python", "node", "nodejs", "deno", "bun", "ruby", "perl", "php", "java", "osascript",
        "sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "csh", "env",
        "uv", "uvx", "npx", "npm", "pnpm", "yarn", "pipx", "pip", "bundle", "rake"
    ]

    /// Whether this program may be marked expected: not an interpreter,
    /// shell or launcher ("python3.14" is python).
    public static func canBeExpected(program: String) -> Bool {
        var name = (program as NSString).lastPathComponent.lowercased()
        while let last = name.last, last.isNumber || last == "." || last == "-" {
            name.removeLast()
        }
        return !name.isEmpty && !runsAnything.contains(name)
    }

    /// The reader's executable within `by`: the expected entry that matches
    /// it, else `by` whole. A decoy read's `by` is the reader's executable
    /// path alone (jit's serve auditor records the path, never arguments),
    /// and a path may hold spaces, so it is never cut at one.
    public static func program(of by: String?, known: [ExpectedReader] = []) -> String? {
        guard let by, !by.isEmpty else {
            return nil
        }
        if let match = known.first(where: { by == $0.program || by.hasPrefix($0.program + " ") }) {
            return match.program
        }
        return by
    }
}

/// One program reading one protected file again and again, with no gap
/// longer than `DecoyBurst.gap`: an editor indexing a folder is one burst,
/// not 1,712 alarms.
public struct DecoyBurst: Equatable, Sendable, Identifiable {
    /// A pause longer than this starts a new burst.
    public static let gap: TimeInterval = 5 * 60

    /// The reader as the audit names it (`by`), for Expected.
    public var by: String?
    /// Its display name ("python3", "Editor").
    public var reader: String?
    public var file: String
    public var reads: Int
    public var first: Date
    public var last: Date
    /// The engine's reason, in the reader's words (DecoyReport.reason).
    public var why: String
    /// A reader the user marked expected for this file.
    public var expected: Bool
    /// How many bursts this row stands for: one program reading one file
    /// several times a day (a server started now and then) is one row.
    public var bursts = 1

    public var id: String {
        "\(by ?? ""):\(file):\(Int(first.timeIntervalSince1970))"
    }

    /// How long the burst lasted, for "in 2 minutes"; nil for a moment,
    /// and for a row of several bursts, whose first and last are apart.
    public var span: TimeInterval? {
        guard bursts == 1 else {
            return nil
        }
        let s = last.timeIntervalSince(first)
        return s >= 60 ? s : nil
    }

    /// Decoy reads (never real ones) of protected files, as bursts, newest
    /// first with expected ones after the rest. With the expected list in
    /// hand, it alone decides, per reader and file: a tag jit wrote before
    /// a mark was taken back is stale. Without it, jit's tag is trusted only
    /// on a read of one file, since it tags the whole read. A reader jit
    /// only guessed at (by_likely) is never expected.
    public static func make(_ events: [SessionEvent], since: Date?, expected: ExpectedReaders?) -> [DecoyBurst] {
        let decoys = events.filter { event in
            event.readDecoy && (since.map { event.date >= $0 } ?? true)
        }.sorted { $0.unixTime < $1.unixTime }
        var open: [String: DecoyBurst] = [:]
        var done: [DecoyBurst] = []
        for event in decoys {
            for file in event.labels ?? [] {
                let key = (event.by ?? "") + "\n" + file
                let isExpected = Self.isExpected(event, file: file, list: expected)
                if var burst = open[key], event.date.timeIntervalSince(burst.last) <= gap {
                    burst.reads += event.count ?? 1
                    burst.last = event.date
                    burst.expected = burst.expected && isExpected
                    open[key] = burst
                    continue
                }
                if let finished = open[key] {
                    done.append(finished)
                }
                open[key] = DecoyBurst(
                    by: event.by, reader: event.by.flatMap { AuditReport.program($0) }, file: file,
                    reads: event.count ?? 1, first: event.date, last: event.date,
                    why: DecoyReport.reason(event), expected: isExpected
                )
            }
        }
        done.append(contentsOf: open.values)
        return merged(done).sorted { ($0.expected ? 1 : 0, -$0.last.timeIntervalSince1970) < (
            $1.expected ? 1 : 0,
            -$1.last.timeIntervalSince1970
        ) }
    }

    static func isExpected(_ event: SessionEvent, file: String, list: ExpectedReaders?) -> Bool {
        if event.byLikely == true {
            return false
        }
        if let list {
            return list.covers(by: event.by, label: file)
        }
        return event.expected == true && (event.labels ?? []).count == 1
    }

    /// One row per program and file: its bursts added up, the latest one's
    /// time and reason, the span only when there was one burst.
    static func merged(_ bursts: [DecoyBurst]) -> [DecoyBurst] {
        var rows: [String: DecoyBurst] = [:]
        for burst in bursts.sorted(by: { $0.last < $1.last }) {
            let key = (burst.by ?? "") + "\n" + burst.file
            guard var row = rows[key] else {
                rows[key] = burst
                continue
            }
            row.reads += burst.reads
            row.bursts += 1
            row.first = burst.first
            row.last = burst.last
            row.why = burst.why
            row.expected = row.expected && burst.expected
            rows[key] = row
        }
        return Array(rows.values)
    }

    /// The programs that read a decoy and are not expected: the menu's
    /// and the headline's number. A read jit could not trace to a program
    /// is not one of them (`untraced`).
    public static func unexpectedPrograms(_ bursts: [DecoyBurst]) -> Int {
        Set(bursts.filter { !$0.expected }.compactMap { $0.by.flatMap { $0.isEmpty ? nil : $0 } }).count
    }

    /// Whether a decoy read reached a reader jit could not name: said on
    /// its own, never counted as a program.
    public static func untraced(_ bursts: [DecoyBurst]) -> Bool {
        bursts.contains { !$0.expected && ($0.by ?? "").isEmpty }
    }

    /// Whether anything unexpected read a decoy: the amber.
    public static func anyUnexpected(_ bursts: [DecoyBurst]) -> Bool {
        unexpectedPrograms(bursts) > 0 || untraced(bursts)
    }
}
