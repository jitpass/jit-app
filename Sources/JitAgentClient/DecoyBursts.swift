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

    /// The reader's executable within `by`: the expected entry that matches
    /// it, else `by` up to its first space (the audit's usual shape).
    public static func program(of by: String?, known: [ExpectedReader] = []) -> String? {
        guard let by, !by.isEmpty else {
            return nil
        }
        if let match = known.first(where: { by == $0.program || by.hasPrefix($0.program + " ") }) {
            return match.program
        }
        return by.split(separator: " ", maxSplits: 1).first.map(String.init)
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

    public var id: String {
        "\(by ?? ""):\(file):\(Int(first.timeIntervalSince1970))"
    }

    /// How long the burst lasted, for "in 2 minutes"; nil for a moment.
    public var span: TimeInterval? {
        let s = last.timeIntervalSince(first)
        return s >= 60 ? s : nil
    }

    /// Decoy reads (never real ones) of protected files, as bursts, newest
    /// first with expected ones after the rest. An event is expected when
    /// jit said so, or, for a live event jit has not labelled yet, when the
    /// expected list covers it.
    public static func make(_ events: [SessionEvent], since: Date?, expected: ExpectedReaders?) -> [DecoyBurst] {
        let decoys = events.filter { event in
            event.readDecoy && (since.map { event.date >= $0 } ?? true)
        }.sorted { $0.unixTime < $1.unixTime }
        var open: [String: DecoyBurst] = [:]
        var done: [DecoyBurst] = []
        for event in decoys {
            for file in event.labels ?? [] {
                let key = (event.by ?? "") + "\n" + file
                let isExpected = event.expected == true || (expected?.covers(by: event.by, label: file) ?? false)
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
        return done.sorted { ($0.expected ? 1 : 0, -$0.last.timeIntervalSince1970) < ($1.expected ? 1 : 0, -$1.last.timeIntervalSince1970) }
    }

    /// The programs that read a decoy and are not expected: the menu's
    /// and the headline's number.
    public static func unexpectedPrograms(_ bursts: [DecoyBurst]) -> Int {
        Set(bursts.filter { !$0.expected }.map { $0.by ?? "" }).count
    }
}
