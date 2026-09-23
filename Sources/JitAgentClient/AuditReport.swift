// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One `jit` invocation as `jit audit --format json` reports it, under
/// `commands`. Args are already redacted by the CLI before they are logged.
public struct AuditCommand: Codable, Sendable, Equatable {
    public var unixNano: Int64
    public var command: String
    public var parent: String?
    public var launchedBy: String?
    public var durationMs: Int64?
    public var success: Bool

    enum CodingKeys: String, CodingKey {
        case unixNano = "unix_nano"
        case command, parent
        case launchedBy = "launched_by"
        case durationMs = "duration_ms"
        case success
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(unixNano) / 1_000_000_000)
    }
}

/// The two halves `jit audit` merges: the command log and the service's
/// session events, the latter in the same shape the socket streams.
public struct AuditReport: Codable, Sendable, Equatable {
    public var commands: [AuditCommand]
    public var authEvents: [SessionEvent]

    enum CodingKeys: String, CodingKey {
        case commands
        case authEvents = "auth_events"
    }

    public init(commands: [AuditCommand], authEvents: [SessionEvent]) {
        self.commands = commands
        self.authEvents = authEvents
    }

    /// Both halves as one timeline, newest first, in the form a list row
    /// renders: when, what kind, who did it, and one line of detail.
    public var rows: [AuditRow] {
        let fromCommands = commands.map { cmd in
            AuditRow(
                id: "cmd:\(cmd.unixNano)",
                date: cmd.date,
                kind: "cmd",
                status: cmd.success ? "ok" : "failed",
                title: cmd.command,
                detail: cmd.launchedBy.map { "launched by \($0)" } ?? "",
                launchedBy: cmd.launchedBy
            )
        }
        let fromEvents = authEvents.map { event in
            AuditRow(
                id: "auth:\(event.unixTime):\(event.kind):\(event.op ?? "")",
                date: event.date,
                kind: event.kind,
                status: event.isDecoyServe ? "decoy" : event.kind,
                title: Self.title(for: event),
                detail: Self.detail(for: event),
                launchedBy: event.launchedBy
            )
        }
        return (fromCommands + fromEvents).sorted { $0.date > $1.date }
    }

    /// The one line that names a session event: who did what. Shared by the
    /// panel's "last event" and the audit rows so they can never disagree.
    /// A use with no caller is the agent serving its own mounts, and says so
    /// rather than printing a question mark.
    public static func title(for event: SessionEvent) -> String {
        let who = event.by.map { String($0.split(separator: "/").last ?? Substring($0)) } ?? ""
        let secrets = event.labels?.joined(separator: ", ") ?? ""
        switch event.kind {
        case "unlock":
            return who.isEmpty ? "unlocked" : "unlocked by \(who)"
        case "lock":
            return "locked"
        case "use":
            return useTitle(event, who: who, what: secrets.isEmpty ? "a secret" : secrets)
        case "denied":
            return who.isEmpty ? "denied" : "denied \(who)"
        case "approved":
            return approvedTitle(event, who: who)
        case "grant_end":
            // The cause is the sentence: "claude's grant revoked". Labels
            // are the paths it covered, on the detail line.
            return event.cause ?? "grant ended"
        case "serve":
            // A decoy serve is the one event the whole design exists for:
            // something read a protected file with no run or consent
            // covering it, and got fake values. Name the reader and say so.
            // Undelivered: opened and closed before anything was written, so
            // nothing was served. Worded as `jit audit` words it.
            let reader = who.isEmpty ? "an unknown reader" : who
            if event.undelivered == true {
                return "opened by \(reader), nothing read"
            }
            return event.isDecoyServe ? "decoy served to \(reader)" : "real values served to \(reader)"
        case "start":
            return "service started"
        default:
            return who.isEmpty ? event.kind : "\(event.kind) · \(who)"
        }
    }

    /// A read that rode a process grant is a different fact from one that
    /// rode a session, and `jit audit` says so; this window must not fold
    /// the two into "used".
    static func useTitle(_ event: SessionEvent, who: String, what: String) -> String {
        if event.op == "grant_use" {
            return who.isEmpty ? "read \(what) via grant" : "\(who) read \(what) via grant"
        }
        if who.isEmpty {
            return event.op == "serve_mounts" ? "served mounts (\(what))" : "used \(what)"
        }
        return "\(who) used \(what)"
    }

    /// A grant's birth is an approval with the grant op; the detail line
    /// carries the sentence that was approved, word for word.
    static func approvedTitle(_ event: SessionEvent, who: String) -> String {
        switch event.op {
        case "grant_create": who.isEmpty ? "grant approved" : "grant approved, asked by \(who)"
        case "grant_extend": who.isEmpty ? "grant extended" : "grant extended, asked by \(who)"
        default: who.isEmpty ? "approved" : "approved \(who)"
        }
    }

    /// The second line: the file for a serve (with the read count when the
    /// agent folded several), the agent's cause otherwise.
    public static func detail(for event: SessionEvent) -> String {
        if event.kind == "serve" {
            var parts: [String] = []
            if let files = event.labels, !files.isEmpty {
                parts.append(files.joined(separator: ", "))
            }
            if let count = event.count, count > 1 {
                parts.append("\(count) reads")
            }
            if let by = event.launchedBy {
                parts.append("launched by \(by)")
            }
            return parts.joined(separator: " · ")
        }
        return event.cause ?? event.launchedBy.map { "launched by \($0)" } ?? ""
    }
}

public struct AuditRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var date: Date
    public var kind: String
    public var status: String
    public var title: String
    public var detail: String
    public var launchedBy: String?
}

/// The filters `jit audit` accepts, rendered to its flags. Empty means
/// unfiltered, the same as the CLI's defaults.
public struct AuditFilter: Sendable, Equatable {
    public var kinds: [String] = []
    public var parent = ""
    public var since = ""
    public var limit = 200

    public init(kinds: [String] = [], parent: String = "", since: String = "", limit: Int = 200) {
        self.kinds = kinds
        self.parent = parent
        self.since = since
        self.limit = limit
    }

    /// The cap the CLI is asked for: the newest `limit` entries for an
    /// hour or a day, everything for a longer range. A fixed 200 was the
    /// bug where "last 7 days" showed one busy afternoon, because two
    /// hundred entries fit in it.
    public var effectiveLimit: Int {
        switch since {
        case "", "7d", "30d": 0
        default: limit
        }
    }

    /// The range as seconds, for the ranges the Audit window offers; nil
    /// for no range (or one this does not read).
    public var sinceSeconds: TimeInterval? {
        guard let unit = since.last, let n = Double(since.dropLast()) else {
            return nil
        }
        switch unit {
        case "m": return n * 60
        case "h": return n * 3600
        case "d": return n * 86400
        default: return nil
        }
    }

    public var arguments: [String] {
        var args = ["audit", "--format", "json", "--limit", String(effectiveLimit)]
        if !kinds.isEmpty {
            args += ["--kind", kinds.joined(separator: ",")]
        }
        if !parent.isEmpty {
            args += ["--parent", parent]
        }
        if !since.isEmpty {
            args += ["--since", since]
        }
        return args
    }
}

public extension SessionEvent {
    /// The first read of a serve aggregate, streamed the moment it happens
    /// and never recorded (jit 1.8.1+). The `serve` event that closes the
    /// aggregate, up to an hour later, is the record.
    static let serveStartKind = "serve_start"

    /// A mount's verdict for a reader outside any grant or consent was the
    /// decoy. Includes readers that left before receiving it; the row's
    /// status and the audit filter go by the verdict, as `jit audit` does.
    var isDecoyServe: Bool {
        kind == "serve" && op == "decoy"
    }

    /// A reader actually received decoy values: what the Decoys count and
    /// the notification say. A reader that received nothing is not news.
    var readDecoy: Bool {
        (kind == "serve" || kind == Self.serveStartKind) && op == "decoy" && undelivered != true
    }
}

public extension AuditReport {
    /// This report with the live `serve_start` notices it does not yet
    /// hold, as `serve` rows. The record of a read lands when its
    /// aggregate closes, up to an hour later, so without this the audit a
    /// decoy notification opens would not show the read it announced.
    /// A notice is dropped once the record exists: the record keeps the
    /// first read's time, reader, verdict and file.
    func addingLive(_ notices: [SessionEvent], filter: AuditFilter, now: Date = Date()) -> AuditReport {
        guard filter.kinds.isEmpty || filter.kinds.contains("serve"), filter.parent.isEmpty else {
            return self
        }
        let oldest = filter.sinceSeconds.map { now.timeIntervalSince1970 - $0 }
        let recorded = Set(authEvents.filter { $0.kind == "serve" }.map(\.serveIdentity))
        var merged = self
        for notice in notices where notice.kind == SessionEvent.serveStartKind {
            if let oldest, TimeInterval(notice.unixTime) < oldest {
                continue
            }
            var event = notice
            event.kind = "serve"
            if !recorded.contains(event.serveIdentity) {
                merged.authEvents.append(event)
            }
        }
        return merged
    }
}

extension SessionEvent {
    /// What a serve notice and the record that follows it share.
    var serveIdentity: String {
        [String(unixTime), by ?? "", op ?? "", (labels ?? []).joined(separator: "\u{1f}"), undelivered == true ? "u" : ""]
            .joined(separator: "\u{1e}")
    }
}
