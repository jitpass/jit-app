// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The one document `jit migrate redact --format json --yes` writes: the
/// files named, whether anything was rewritten, the cache files redacted
/// (`copies` = tokens replaced) and left, errors, and the text report.
/// Vendor names and paths, never a value. There is no backup and no undo:
/// the marker in the file is the record.
public struct RedactReport: Codable, Sendable, Equatable {
    public var files: [String]
    public var applied: Bool
    public var caches: MigrateReport.Caches
    public var errors: [String]
    public var report: String

    public init(files: [String], applied: Bool, caches: MigrateReport.Caches, errors: [String], report: String) {
        self.files = files
        self.applied = applied
        self.caches = caches
        self.errors = errors
        self.report = report
    }

    public static func parse(_ output: String) throws -> RedactReport {
        guard let start = output.range(of: "{"), let end = output.range(of: "}", options: .backwards),
              start.lowerBound < end.upperBound
        else {
            throw MigrateReportError.noDocument
        }
        return try JSONDecoder().decode(RedactReport.self, from: Data(String(output[start.lowerBound ..< end.upperBound]).utf8))
    }

    public var tokensRedacted: Int {
        caches.removed.reduce(0) { $0 + ($1.copies ?? 0) }
    }
}

public extension ScanWording {
    /// The banner after a Redact: "Redacted 7 tokens in 3 files · Claude
    /// Code's transcripts and edit history · 1 left, Claude Code is writing
    /// it". Nothing to redact, or the error first and the partial result
    /// after it, since those edits are real.
    static func redactOutcome(_ report: RedactReport) -> ProtectOutcome {
        var parts: [String] = []
        if let error = report.errors.last {
            parts.append("Redact did not finish · " + error)
        } else if !report.applied, report.caches.left.isEmpty {
            return ProtectOutcome(title: "Nothing to redact", failed: false)
        }
        let n = report.tokensRedacted
        if n > 0 {
            parts
                .append("Redacted \(n) token" + (n == 1 ? "" : "s") + " in \(report.caches.removed.count) file" +
                    (report.caches.removed.count == 1 ? "" : "s"))
            var places: [String] = []
            for file in report.caches.removed {
                let place = "\(file.agent)'s \(file.area)"
                if !places.contains(place) {
                    places.append(place)
                }
            }
            parts.append(places.joined(separator: " and "))
        }
        if !report.caches.left.isEmpty {
            let live = report.caches.left.filter { $0.kind == "live" }
            let n = report.caches.left.count
            var left = "\(n) left"
            if let first = live.first {
                left += live.count == 1 ? ", \(first.agent) is writing it" : ", \(first.agent) is writing them"
            } else if let first = report.caches.left.first, first.kind == "binary" {
                left += n == 1 ? ", a binary store jit won't rewrite" : ", binary stores jit won't rewrite"
            }
            parts.append(left)
        }
        return ProtectOutcome(title: parts.joined(separator: " · "), failed: !report.errors.isEmpty)
    }
}

public extension ScanNotices {
    /// After a scheduled scan redacted on its own: "Tuesday's scan redacted
    /// 7 tokens in Claude Code's caches" / "3 files. 1 left: Claude Code
    /// was writing it. Click to open Findings." nil when nothing changed.
    static func redacted(
        _ report: RedactReport,
        at: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> ScanNotice? {
        let n = report.tokensRedacted
        guard n > 0 else {
            return nil
        }
        let day = ScanWording.dayWord(at, now: now, calendar: calendar, locale: locale)
        var agents: [String] = []
        for file in report.caches.removed where !agents.contains(file.agent) {
            agents.append(file.agent)
        }
        let who = agents.count == 1 ? "\(agents[0])'s caches" : "AI agent caches"
        let title = day.prefix(1).uppercased() + day.dropFirst() + "'s scan redacted \(n) token" + (n == 1 ? "" : "s") + " in " + who
        var body = "\(report.caches.removed.count) file" + (report.caches.removed.count == 1 ? "" : "s") + "."
        let live = report.caches.left.filter { $0.kind == "live" }
        if !live.isEmpty {
            body += " \(live.count) left: \(live[0].agent) was writing " + (live.count == 1 ? "it." : "them.")
        }
        return ScanNotice(title: title, body: body + " Click to open Findings.")
    }
}
