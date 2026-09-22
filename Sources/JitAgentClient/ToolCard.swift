// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One tool that runs through jit, as the Tools window draws it: which
/// card it sits in, what jit hands it, and one fact — health, last use,
/// other readers, sessions. The listing says what jit did; the audit says
/// whether it is working.
public struct ToolCard: Equatable, Sendable {
    public enum Tier: Sendable {
        /// A broken shim, or a captured session that has run out.
        case fixNow
        /// Wrapped, and its key has never been read: another copy on PATH
        /// may be answering first.
        case silent
        case working
    }

    public enum Verb: Equatable, Sendable {
        case repair
        /// `Log In…`: the mint command, in the terminal (the IdP's MFA).
        case logIn(String)
        case verify
        case none
    }

    public var tool: String
    public var tier: Tier
    /// What jit hands the tool, in mono: its vault paths, or what it captures.
    public var detail: String
    public var fact: String
    public var verb: Verb
    /// The header's line for this tool; nil when it asks nothing.
    public var todo: String?

    public static func make(_ record: ToolRecord, sessions: [CLISession], activity: ToolActivity?, now: Date = Date()) -> ToolCard {
        if record.wrapped, !record.isHealthy {
            return ToolCard(
                tool: record.tool, tier: .fixNow, detail: detail(record),
                fact: record.stateLabel + (record.shimDetail.map { " · " + $0 } ?? ""),
                verb: .repair, todo: record.tool + "'s " + record.stateLabel.replacingOccurrences(of: "shim ", with: "shim is ")
            )
        }
        if let expired = sessions.first(where: { !$0.live }) {
            return expiredCard(record, expired: expired, sessions: sessions, now: now)
        }
        let verb: Verb = record.verifyHint != nil && record.isProtected ? .verify : .none
        if record.kind == "capture" {
            let live = sessions.filter(\.live)
            let fact = live.isEmpty ? "catching logins · no session yet"
                : live.map { $0.profile + " live" + ($0.expires.map { ", " + left($0, now: now) } ?? "") }.joined(separator: " · ")
            return ToolCard(tool: record.tool, tier: .working, detail: detail(record), fact: fact, verb: verb, todo: nil)
        }
        return readCard(record, activity: activity, verb: verb, now: now)
    }

    /// A captured session has run out: the next call fails until the tool
    /// logs in again, in the terminal.
    private static func expiredCard(_ record: ToolRecord, expired: CLISession, sessions: [CLISession], now: Date) -> ToolCard {
        var parts = [expired.profile + " expired" + (expired.expires.map { " " + when($0, now: now) } ?? "")]
        if let alive = sessions.first(where: \.live) {
            parts.append(alive.profile + " live" + (alive.expires.map { ", " + left($0, now: now) } ?? ""))
        }
        if sessions.count > 1 {
            parts.append("\(sessions.count) sessions")
        }
        return ToolCard(
            tool: record.tool, tier: .fixNow, detail: detail(record), fact: parts.joined(separator: " · "),
            verb: expired.mint.map { .logIn($0) } ?? .none,
            todo: expired.profile + "'s session ran out" + (expired.expires.map { " " + when($0, now: now) } ?? "")
        )
    }

    /// What the audit says about the key: never read (silent), or read,
    /// when, by whom, and by whom else.
    private static func readCard(_ record: ToolRecord, activity: ToolActivity?, verb: Verb, now: Date) -> ToolCard {
        guard let activity else {
            return ToolCard(tool: record.tool, tier: .working, detail: detail(record), fact: "reads not checked yet", verb: verb, todo: nil)
        }
        if activity.reads == 0 {
            let since = record.addedUnix.map { " since " + day(Date(timeIntervalSince1970: TimeInterval($0))) } ?? " this week"
            return ToolCard(
                tool: record.tool, tier: .silent, detail: detail(record),
                fact: "0 reads" + since + " · another copy on PATH may be answering first",
                verb: verb, todo: record.tool + " is wrapped but has never read its key"
            )
        }
        var parts: [String] = []
        if let last = activity.lastRead {
            parts.append("last read " + when(last, now: now) + (activity.readers.first.map { " by " + $0 } ?? ""))
        }
        parts.append("\(activity.reads) read" + (activity.reads == 1 ? "" : "s") + " this week")
        let others = activity.others(than: record.tool)
        parts.append(others.isEmpty ? "no other program" : "also read by " + others.joined(separator: ", "))
        return ToolCard(
            tool: record.tool,
            tier: .working,
            detail: detail(record),
            fact: parts.joined(separator: " · "),
            verb: verb,
            todo: nil
        )
    }

    static func detail(_ record: ToolRecord) -> String {
        if record.kind == "capture" {
            return "captures " + (record.capture ?? "logins")
        }
        if record.isNative {
            return "native · " + (record.doc.map { String($0.prefix(40)) } ?? "protected in place")
        }
        let paths = record.injects.compactMap(\.vaultPath)
        if !paths.isEmpty {
            return paths.joined(separator: " · ")
        }
        if let mount = record.with {
            return "grants the " + mount + " mount"
        }
        return record.kind
    }

    static func when(_ date: Date, now: Date) -> String {
        ScanWording.when(date, now: now)
    }

    static func left(_ date: Date, now: Date) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 3600 {
            return "\(Int(seconds / 60))m left"
        }
        return "\(Int(seconds / 3600))h left"
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}
