// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What one agent did through jit in the audit's range: the card's
/// "This week" row. Counted from the log, never inferred.
public struct AgentActivity: Equatable, Sendable {
    /// `jit run` and every other jit command the agent launched.
    public var runs = 0
    /// Real values a mount or a use served to a program the agent launched.
    public var realValues = 0
    /// Decoy reads by the agent's own program.
    public var decoyReads = 0
    /// Consent prompts the agent's tools raised: approved plus declined.
    public var prompts = 0

    public init(runs: Int = 0, realValues: Int = 0, decoyReads: Int = 0, prompts: Int = 0) {
        self.runs = runs
        self.realValues = realValues
        self.decoyReads = decoyReads
        self.prompts = prompts
    }
}

public extension AuditReport {
    /// The activity of the agent whose CLI is `tool` ("claude"): commands
    /// it launched, and session events its processes caused. The audit
    /// names the launching ancestor as the tool's own name.
    func agentActivity(tool: String) -> AgentActivity {
        var activity = AgentActivity()
        for cmd in commands where Self.program(cmd.launchedBy) == tool {
            activity.runs += 1
        }
        for event in authEvents {
            let launched = Self.program(event.launchedBy) == tool
            let reader = Self.program(event.by) == tool
            switch event.kind {
            case "use" where launched:
                activity.realValues += event.count ?? 1
            case "serve" where event.op == "real" && (launched || reader):
                activity.realValues += event.count ?? 1
            case "serve" where event.readDecoy && (launched || reader):
                activity.decoyReads += event.count ?? 1
            case "approved", "denied":
                if launched || reader {
                    activity.prompts += 1
                }
            default:
                break
            }
        }
        return activity
    }

    /// The program named by an audit field: the first word's last path
    /// segment, so "/opt/homebrew/bin/claude --resume" is "claude".
    static func program(_ field: String?) -> String? {
        guard let first = field?.split(separator: " ", maxSplits: 1).first, !first.isEmpty else {
            return nil
        }
        return String(first.split(separator: "/").last ?? first)
    }
}
