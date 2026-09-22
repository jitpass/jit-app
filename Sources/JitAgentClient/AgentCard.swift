// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One agent's card in the AI Agents window: what it has in its files,
/// what it can reach, what it did, and its key — each row one fact in the
/// numbers Findings, the service and the audit hold, so the card can never
/// say "all set" over a window that says otherwise. An agent is not a tool:
/// it records. That is why the first row is what it has seen.
public struct AgentCard: Equatable, Sendable {
    public enum State: Sendable {
        case red, amber, green
    }

    public struct Input: Sendable {
        public var tool: String
        public var label: String
        public var key: ToolKeyState
        public var wrapped: Bool
        public var healthy: Bool
        public var stateLabel: String
        /// nil until a whole-Mac scan has run: the files are unknown, not clean.
        public var exposure: AgentExposure?
        /// Findings in its files the previous scan did not have.
        public var newCopies: Int
        public var protectedFiles: Int
        public var mcpKeysInTheOpen: Int
        public var grantUntil: Date?
        /// nil when the service is not running.
        public var consent: Bool?
        /// nil until the audit has been read.
        public var activity: AgentActivity?
        public var redactsAfterScan: Bool
        public var home: String

        public init(
            tool: String, label: String, key: ToolKeyState, wrapped: Bool, healthy: Bool, stateLabel: String,
            exposure: AgentExposure?, newCopies: Int, protectedFiles: Int, mcpKeysInTheOpen: Int, grantUntil: Date?,
            consent: Bool?, activity: AgentActivity?, redactsAfterScan: Bool, home: String
        ) {
            self.tool = tool
            self.label = label
            self.key = key
            self.wrapped = wrapped
            self.healthy = healthy
            self.stateLabel = stateLabel
            self.exposure = exposure
            self.newCopies = newCopies
            self.protectedFiles = protectedFiles
            self.mcpKeysInTheOpen = mcpKeysInTheOpen
            self.grantUntil = grantUntil
            self.consent = consent
            self.activity = activity
            self.redactsAfterScan = redactsAfterScan
            self.home = home
        }
    }

    public var state: State
    /// The header's line for this agent; nil when it asks nothing.
    public var todo: String?
    /// The card's note: since the last scan, in one sentence.
    public var since: String
    public var inFiles: String
    public var canReach: String
    public var thisWeek: String
    public var key: String
    public var redactFact: String
    /// The verbs the "In its files" row carries.
    public var offersClean: Bool
    public var redactCount: Int

    public static func make(_ input: Input) -> AgentCard {
        let files = filesFact(input)
        let key = keyFact(input)
        let reach = reachFact(input)
        var state = State.green
        if key.amber || reach.amber {
            state = .amber
        }
        if files.red {
            state = .red
        }
        let exposure = input.exposure ?? AgentExposure()
        return AgentCard(
            state: state,
            todo: files.red ? todoLine(input, exposure) : nil,
            since: sinceFact(input, exposure),
            inFiles: files.text,
            canReach: reach.text,
            thisWeek: weekFact(input.activity),
            key: key.text,
            redactFact: input.redactsAfterScan
                ? "on · tokens it records become markers after each scheduled scan"
                : "off · tokens it records stay until you redact them by hand",
            offersClean: exposure.copies > 0,
            redactCount: exposure.tokens
        )
    }

    private static func todoLine(_ input: Input, _ exposure: AgentExposure) -> String {
        var parts: [String] = []
        if exposure.vaultSecrets > 0 {
            parts.append("copies of " + count(exposure.vaultSecrets, "vaulted secret"))
        } else if exposure.copies > 0 {
            parts.append(count(exposure.copies, "cached copy", plural: "cached copies"))
        }
        if exposure.tokens > 0 {
            parts.append(count(exposure.tokens, (parts.isEmpty ? "" : "other ") + "token"))
        }
        return input.label + "'s files hold " + parts.joined(separator: " and ")
    }

    private static func sinceFact(_ input: Input, _: AgentExposure) -> String {
        guard input.exposure != nil else {
            return "Not searched yet: a whole-Mac scan fills in its files."
        }
        var parts =
            [input.newCopies == 0 ? "nothing new in its files" : count(input.newCopies, "new copy", plural: "new copies") + " in its files"]
        if let activity = input.activity {
            parts.append(count(activity.runs, "run") + " through jit")
            parts.append(activity.prompts == 0 ? "nothing asked of you" : count(activity.prompts, "prompt"))
        }
        return "Since the last scan: " + parts.joined(separator: " · ") + "."
    }

    private static func filesFact(_ input: Input) -> (text: String, red: Bool) {
        guard let exposure = input.exposure else {
            return ("not searched yet", false)
        }
        guard !exposure.isEmpty else {
            return ("no copy of a secret in its files", false)
        }
        var parts: [String] = []
        if exposure.copies > 0 {
            let what = exposure.vaultSecrets > 0 ? "copies of " + count(exposure.vaultSecrets, "vaulted secret") : count(
                exposure.copies,
                "cached copy",
                plural: "cached copies"
            )
            parts.append(what + " in " + count(exposure.copyFiles, "file"))
        }
        if exposure.tokens > 0 {
            parts.append(count(exposure.tokens, "token") + " by format in " + count(exposure.tokenFiles, "file"))
        }
        return (parts.joined(separator: " · "), true)
    }

    private static func reachFact(_ input: Input) -> (text: String, amber: Bool) {
        var parts = [count(input.protectedFiles, "protected file") + " through jit"]
        var amber = false
        switch input.consent {
        case true: parts.append("a real value goes to it only after your Touch ID")
        case false:
            parts.append("a real value goes to it without asking you")
            amber = true
        default: parts.append("the service is not running, so nothing is served")
        }
        if input.mcpKeysInTheOpen > 0 {
            parts.append(count(input.mcpKeysInTheOpen, "MCP key") + " in the open")
            amber = true
        } else {
            parts.append("no MCP key in the open")
        }
        parts.append(input.grantUntil.map { "grant until " + SessionState.clock($0) } ?? "no grant")
        return (parts.joined(separator: " · "), amber)
    }

    private static func weekFact(_ activity: AgentActivity?) -> String {
        guard let activity else {
            return "not read yet"
        }
        return [
            count(activity.runs, "run") + " through jit",
            count(activity.realValues, "real value") + " disclosed",
            count(activity.decoyReads, "decoy read"),
            count(activity.prompts, "prompt")
        ].joined(separator: " · ")
    }

    private static func keyFact(_ input: Input) -> (text: String, amber: Bool) {
        switch input.key {
        case .protected:
            if input.wrapped, !input.healthy {
                return ("wrapped, but the " + input.stateLabel, true)
            }
            return ("wrapped · read from the vault for its own process", false)
        case let .found(source) where source.hasPrefix("~") || source.hasPrefix("/"):
            return ("in the open, " + ScanNotices.abbreviate(source, home: input.home), true)
        case .found:
            return ("in \(input.tool)'s own login, not in the vault", true)
        case .none:
            return ("none on this Mac · nothing for jit to move", false)
        case .unknown:
            return ("not checked yet", false)
        }
    }

    static func count(_ n: Int, _ singular: String, plural: String? = nil) -> String {
        "\(n) " + (n == 1 ? singular : plural ?? singular + "s")
    }
}
