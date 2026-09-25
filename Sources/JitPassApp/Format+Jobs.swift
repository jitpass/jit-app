// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// The AI Jobs window's words, in one place. The drawing they follow is the
/// Jobs mockup (docs/design/mockups/Jobs.html, jit design/agent-jobs.md).
extension Format {
    // MARK: - The window

    static func jobsHeadline(_ board: JobsBoard) -> String {
        if board.isEmpty, board.proposals.isEmpty {
            return "AI Jobs"
        }
        var head = jobsCount(board.jobCount)
        if board.needsYou > 0 {
            head += " · " + (board.needsYou == 1 ? "1 needs you" : "\(board.needsYou) need you")
        }
        return head
    }

    static func jobsSubline(_ board: JobsBoard) -> String {
        board.isEmpty
            ? "A job lets AI tools run one command with secrets. They see what it prints, never the values."
            : "Each runs only as you approved it. A changed file stops it until you look."
    }

    static let jobsEmptyTitle = "No AI tool can run anything with your secrets"
    static let jobsEmptyMessage = "Approve a job when you want Claude or another agent to run a script that needs a key, " +
        "without being able to read the key."

    static func jobsCount(_ n: Int) -> String {
        n == 1 ? "1 job" : "\(n) jobs"
    }

    /// The footer states; it configures nothing.
    static func jobsFooter(_ board: JobsBoard) -> String {
        let runs = board.runs == 1 ? "1 run" : "\(board.runs) runs"
        return jobsCount(board.jobCount) + " · " + runs + " since each was approved"
    }

    // MARK: - A stopped job

    static func jobStoppedEyebrow(_ job: JobStatus) -> String {
        job.jobState == .rotated ? "Rotated" : "Changed"
    }

    static func jobStoppedTitle(_ job: JobStatus) -> String {
        "\(job.name) stopped running"
    }

    /// What stopped it, in the service's own words, and the way back.
    static func jobStoppedNote(_ job: JobStatus) -> String {
        let why: String = if let change = job.changes?.first {
            change.kind == "rewritten"
                ? "\(change.path) was written to since you approved it, though its content matches"
                : "\(change.path) \(change.kind) since you approved it"
        } else if let refusal = job.lastRefusal, !refusal.isEmpty {
            refusal
        } else {
            job.jobState == .rotated ? "A secret it uses was rotated" : "Its files changed"
        }
        return why + ". jit refuses the job until you look at the change and approve it again."
    }

    // MARK: - A job's row

    /// "· python list_guest_users.py": the program's name and its arguments.
    static func jobCommand(_ job: JobStatus) -> String {
        guard let first = job.argv.first else {
            return ""
        }
        let program = (first as NSString).lastPathComponent
        return "· " + ([program] + job.argv.dropFirst()).joined(separator: " ")
    }

    static func jobAsks(_ job: JobStatus) -> String {
        job.asksEachTime ? "Asks each time" : "Runs without asking"
    }

    static func jobFact(_ job: JobStatus, now: Date = Date()) -> String {
        var parts: [String] = []
        if job.jobState != .ready {
            if let caller = job.lastCaller, !caller.isEmpty {
                parts.append("Refused \(caller)")
            } else {
                parts.append("Stopped")
            }
        } else if let last = job.lastRun {
            let who = job.lastCaller.map { $0.isEmpty ? "An AI tool" : $0 } ?? "An AI tool"
            parts.append("\(who) ran it \(ago(last, now: now))")
            parts.append(job.lastExit.map { $0 == 0 ? "worked" : "exit \($0)" } ?? "worked")
            if let hidden = job.lastHidden, hidden > 0 {
                parts.append(hidden == 1 ? "hid 1 value" : "hid \(hidden) values")
            }
        } else {
            parts.append("Not run yet")
        }
        parts.append(jobAsks(job))
        if let count = job.secrets?.count, count > 0 {
            parts.append(count == 1 ? "1 secret" : "\(count) secrets")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - The AI apps that can ask

    static let jobsAppsEyebrow = "AI apps that can ask"

    static func claudeDesktopFact(_ status: MCPStatus?) -> String {
        guard let status else {
            return "Checking…"
        }
        if status.isConnected {
            return "Connected · Cowork asks through jit mcp"
        }
        return status.installed ? "Set up for a jit that is no longer there" : "Not connected"
    }

    static let terminalAgentsFact = "Always · claude, codex and others ask with jit job run"

    // MARK: - Remove, connect

    static func removeJobTitle(_ job: JobStatus) -> String {
        "Remove \(job.name)?"
    }

    /// Leads with what happens, then what undoing it costs.
    static func removeJobMessage(_ job: JobStatus) -> String {
        var text = "AI tools can no longer run it."
        if !job.asksEachTime {
            text += " Its key is deleted."
        }
        return text + " Approving it again is a new Touch ID, not an undo."
    }

    static func removedJobBanner(_ job: JobStatus) -> String {
        "Removed \(job.name). AI tools can no longer run it."
    }

    static let connectedBanner = "Claude Desktop will start jit's MCP server. Quit and reopen Claude Desktop to pick this up."
    static let disconnectedBanner = "Claude Desktop no longer starts jit's MCP server. Quit and reopen Claude Desktop to pick this up."
}
