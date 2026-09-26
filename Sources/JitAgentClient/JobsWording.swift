// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The AI Jobs window's sentences that say something about jit's state,
/// here rather than in the app's `Format` so a test can hold them to what
/// the code knows. `Format` forwards to them.
public enum JobsWording {
    /// The window with no job. About jobs only: a standing grant can still
    /// hand a tool a secret, and this window does not know about grants,
    /// so it never says no tool can.
    public static let emptyTitle = "No AI jobs yet"

    /// A job's row under its name: what last happened, whether it asks,
    /// how many secrets. Sentence case: only the line's first word is
    /// capitalised, and the first word may be a program's name
    /// ("claude ran it…"), which keeps its own case.
    public static func fact(_ job: JobStatus, ago: (Date) -> String) -> String {
        var parts: [String] = []
        switch job.rowState {
        case .stopped:
            if let caller = job.lastCaller, !caller.isEmpty {
                parts.append("Refused \(caller)")
            } else {
                parts.append("Stopped")
            }
        case .notRunning:
            parts.append(notRunning(job))
        case .ready:
            parts.append(contentsOf: ran(job, ago: ago))
        }
        parts.append(asks(job))
        if let count = job.secrets?.count, count > 0 {
            parts.append(count == 1 ? "1 secret" : "\(count) secrets")
        }
        return parts.joined(separator: " · ")
    }

    /// A job whose skipped runs went on: how many, and jit's reason for
    /// the last, word for word. It is not stopped, so nothing here says so.
    public static func notRunning(_ job: JobStatus) -> String {
        let head = (job.skips ?? 0) > 1 ? "Hasn't run the last \(job.skips ?? 0) times" : "Hasn't run the last few times"
        guard let why = job.lastRefusal, !why.isEmpty else {
            return head
        }
        return head + ": " + why
    }

    private static func ran(_ job: JobStatus, ago: (Date) -> String) -> [String] {
        var parts: [String] = []
        if let last = job.lastRun {
            let who = job.lastCaller.map { $0.isEmpty ? "An AI tool" : $0 } ?? "An AI tool"
            parts.append("\(who) ran it \(ago(last))")
            parts.append(job.lastExit.map { $0 == 0 ? "worked" : "exit \($0)" } ?? "worked")
            if let hidden = job.lastHidden, hidden > 0 {
                parts.append(hidden == 1 ? "hid 1 value" : "hid \(hidden) values")
            }
        } else {
            parts.append("Not run yet")
        }
        return parts
    }

    /// Mid-line on the row, so lower case.
    public static func asks(_ job: JobStatus) -> String {
        job.asksEachTime ? "asks each time" : "runs without asking"
    }

    /// An AI app's row. An entry that is installed but can't start is
    /// said as `jit mcp status` says it: the app can't tell a jit that is
    /// gone from one older than AI jobs, so it names both.
    public static func mcpFact(_ app: MCPApp, _ status: MCPStatus?) -> String {
        guard let status else {
            return "Checking…"
        }
        if status.isConnected {
            return "Connected · " + app.via
        }
        return status.installed ? "Set up for a jit that is gone, or older than AI jobs" : "Not connected"
    }
}
