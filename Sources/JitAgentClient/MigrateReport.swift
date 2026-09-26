// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The one document `jit migrate <path> --format json --yes` writes: what
/// the run vaulted, what its agent-cache sweep removed and left, its
/// errors, and the text it would have printed. Names and paths, never a
/// value (docs/reference/migrate-json.md in the jit repo).
public struct MigrateReport: Codable, Sendable, Equatable {
    public var targets: [String]
    public var applied: Bool
    /// Variable names this run stored, once each: "NOTION_TOKEN".
    public var vaulted: [String]
    public var caches: Caches
    public var errors: [String]
    /// The text output the run would have printed.
    public var report: String

    public struct Caches: Codable, Sendable, Equatable {
        public var removed: [CacheFile]
        public var left: [CacheFile]

        public init(removed: [CacheFile] = [], left: [CacheFile] = []) {
            self.removed = removed
            self.left = left
        }
    }

    /// One cache file the sweep rewrote (`copies` spans removed) or left
    /// in place (`kind`: live, binary, hardlink; `reason` in jit's words).
    public struct CacheFile: Codable, Sendable, Equatable {
        public var agent: String
        public var area: String
        public var path: String
        public var copies: Int?
        public var kind: String?
        public var reason: String?

        public init(agent: String, area: String, path: String, copies: Int? = nil, kind: String? = nil, reason: String? = nil) {
            self.agent = agent
            self.area = area
            self.path = path
            self.copies = copies
            self.kind = kind
            self.reason = reason
        }
    }

    public init(targets: [String], applied: Bool, vaulted: [String], caches: Caches, errors: [String], report: String) {
        self.targets = targets
        self.applied = applied
        self.vaulted = vaulted
        self.caches = caches
        self.errors = errors
        self.report = report
    }

    /// Parses the document out of what the command printed. Anything
    /// around it (a progress line that reached the same pipe) is ignored:
    /// the document is the text from the first `{` on a line to the last
    /// `}`.
    public static func parse(_ output: String) throws -> MigrateReport {
        guard let start = output.range(of: "{"), let end = output.range(of: "}", options: .backwards),
              start.lowerBound < end.upperBound
        else {
            throw MigrateReportError.noDocument
        }
        let json = String(output[start.lowerBound ..< end.upperBound])
        return try JSONDecoder().decode(MigrateReport.self, from: Data(json.utf8))
    }

    /// The credential spans the sweep removed, in total.
    public var removedCopies: Int {
        caches.removed.reduce(0) { $0 + ($1.copies ?? 0) }
    }
}

public enum MigrateReportError: Error, Equatable {
    case noDocument
}

/// What the Findings window's banner says after a Protect: the result,
/// in one line, from the report's fields.
public struct ProtectOutcome: Equatable, Sendable {
    public var title: String
    public var failed: Bool
}

public extension ScanWording {
    /// "Protected ~/notion/.env · NOTION_TOKEN is in the vault · 8 cached
    /// copies removed · 1 file left in Claude Code's transcripts". Or, when
    /// the targets held nothing to move, "Nothing to protect in
    /// ~/notion/.env". Or, on an error, "Protect did not finish · <error>"
    /// — and the partial result after it, since those edits are real.
    /// `home` is the user's home directory, so paths read as `~/…`.
    static func protectOutcome(_ report: MigrateReport, home: String) -> ProtectOutcome {
        let target = targetsPhrase(report.targets, home: home)
        var parts: [String] = []
        if let error = report.errors.last {
            parts.append("Protect did not finish · " + error)
        } else if !report.applied {
            return ProtectOutcome(title: "Nothing to protect in " + target, failed: false)
        } else {
            parts.append("Protected " + target)
        }
        switch report.vaulted.count {
        case 0: break
        case 1: parts.append(report.vaulted[0] + " is in the vault")
        case 2, 3: parts.append(report.vaulted.joined(separator: ", ") + " are in the vault")
        default: parts.append("\(report.vaulted.count) secrets are in the vault")
        }
        let removed = report.removedCopies
        if removed > 0 {
            parts.append("\(removed) cached cop" + (removed == 1 ? "y" : "ies") + " removed")
        }
        if !report.caches.left.isEmpty {
            let places = ScanWording.agentPlaces(report.caches.left.map { (agent: $0.agent, area: $0.area) })
            let n = report.caches.left.count
            parts.append("\(n) file" + (n == 1 ? "" : "s") + " left in " + places.joined(separator: " and "))
        }
        return ProtectOutcome(title: parts.joined(separator: " · "), failed: !report.errors.isEmpty)
    }

    /// The empty Findings body after a scan that found nothing: what was
    /// read, and when the schedule looks again.
    static func cleanMessage(
        filesRead: Int,
        schedule: ScanSchedule,
        last: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let files = filesRead.formatted(.number.locale(locale))
        var text = "\(files) files read, including every agent cache."
        switch schedule {
        case .off: text += " Nothing runs on its own; scan again whenever you like."
        case .launch: text += " The next scan runs when JitPass starts."
        default:
            let next = nextRunFact(schedule: schedule, last: last, now: now, calendar: calendar, locale: locale)
            text += " The " + next.replacingOccurrences(of: "next ", with: "next scheduled scan is ") + "."
        }
        return text
    }

    static func targetsPhrase(_ targets: [String], home: String) -> String {
        switch targets.count {
        case 0: "the file"
        case 1: ScanNotices.abbreviate(targets[0], home: home)
        default: "\(targets.count) files"
        }
    }
}
