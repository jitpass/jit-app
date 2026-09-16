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
                detail: cmd.launchedBy.map { "launched by \($0)" } ?? ""
            )
        }
        let fromEvents = authEvents.map { event in
            AuditRow(
                id: "auth:\(event.unixTime):\(event.kind):\(event.op ?? "")",
                date: event.date,
                kind: event.kind,
                status: event.kind,
                title: Self.title(for: event),
                detail: event.cause ?? event.launchedBy.map { "launched by \($0)" } ?? ""
            )
        }
        return (fromCommands + fromEvents).sorted { $0.date > $1.date }
    }

    static func title(for event: SessionEvent) -> String {
        let who = event.by.map { String($0.split(separator: "/").last ?? Substring($0)) } ?? ""
        switch event.kind {
        case "unlock": return who.isEmpty ? "unlocked" : "unlocked by \(who)"
        case "lock": return "locked"
        case "use": return who.isEmpty ? "used a secret" : "\(who) used a secret"
        case "denied": return who.isEmpty ? "denied" : "denied \(who)"
        case "approved": return who.isEmpty ? "approved" : "approved \(who)"
        default: return who.isEmpty ? event.kind : "\(event.kind) · \(who)"
        }
    }
}

public struct AuditRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var date: Date
    public var kind: String
    public var status: String
    public var title: String
    public var detail: String
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

    public var arguments: [String] {
        var args = ["audit", "--format", "json", "--limit", String(limit)]
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
