// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

// MARK: - AI Agents: what each agent can run

extension Format {
    /// "3 AI jobs, never seeing their keys · ran notion-guests 5 minutes ago".
    /// The last run is this agent's own, matched on the name the service
    /// recorded for who asked ("claude" for the CLI, "Claude" for the app).
    static func agentCanRun(caller: String, jobs: [JobStatus], now: Date = Date()) -> String {
        guard !jobs.isEmpty else {
            return "No AI jobs yet"
        }
        var text = (jobs.count == 1 ? "1 AI job" : "\(jobs.count) AI jobs") + ", never seeing their keys"
        let mine = jobs.filter { $0.lastCaller == caller && $0.lastRun != nil }
        if let last = mine.max(by: { ($0.lastRunUnix ?? 0) < ($1.lastRunUnix ?? 0) }), let when = last.lastRun {
            text += " · ran \(last.name) \(ago(when, now: now))"
        }
        return text
    }

    /// What the app is, on its connected card.
    static func appNote(_ app: MCPApp) -> String {
        switch app {
        case .claudeDesktop:
            "An app, not a command line tool. Its Cowork shell runs in a Linux VM, so it can't run jit itself. " +
                "It asks through AI Jobs."
        case .cursor:
            "An editor with an agent, not a command line tool. Its agent asks through AI Jobs."
        }
    }

    static func appNotConnectedNote(_ app: MCPApp) -> String {
        switch app {
        case .claudeDesktop:
            "Installed, but its Cowork shell can't reach jit. " +
                "Connect it and Claude can run scripts you approve, without seeing their keys."
        case .cursor:
            "Installed, but not connected to jit. " +
                "Connect it and its agent can run scripts you approve, without seeing their keys."
        }
    }

    static func appAsksThrough(_ app: MCPApp) -> String {
        "jit mcp, in \(app.name)'s settings"
    }

    static let onboardingClaudeDesktopTitle = "Let Claude Desktop run your scripts without seeing keys"
    static let onboardingClaudeDesktopDetail = "Lets Claude ask to run your scripts. You approve each one first."
}
