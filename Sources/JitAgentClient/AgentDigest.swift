// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One agent, in one line of facts, in a fixed order — key · copies ·
/// reads · grant — so the eye compares down the column. The AI Agents
/// window is a digest: every fact here lives in another window (Tools,
/// Findings, Decoys, Grants) and the row links to the home of the one that
/// needs the reader. It owns no fact and offers no verb of its own
/// (design/scan-and-protect.md D10).
public struct AgentDigest: Equatable, Sendable {
    /// Where a fact lives.
    public enum Home: String, Sendable {
        case tools, findings, decoys, grants

        public var title: String {
            switch self {
            case .tools: "Tools"
            case .findings: "Findings"
            case .decoys: "Decoys"
            case .grants: "Grants"
            }
        }
    }

    /// The row's dot: the worst of its facts. `unknown` is a fact not
    /// checked yet, which lowers nothing.
    public enum State: Sendable {
        case red, amber, green
    }

    public struct Input: Sendable {
        public var tool: String
        public var key: ToolKeyState
        public var wrapped: Bool
        public var healthy: Bool
        /// The wrap's own state word when it is not healthy ("shim is
        /// missing"), from `jit wrap list`.
        public var stateLabel: String
        public var scanned: Bool
        public var copies: Int
        public var areas: [String]
        /// Decoy reads by this agent's programs in the last day; nil when
        /// the audit has not been read yet.
        public var readsToday: Int?
        public var grantUntil: Date?
        public var home: String

        public init(
            tool: String, key: ToolKeyState, wrapped: Bool, healthy: Bool, stateLabel: String, scanned: Bool,
            copies: Int, areas: [String], readsToday: Int?, grantUntil: Date?, home: String
        ) {
            self.tool = tool
            self.key = key
            self.wrapped = wrapped
            self.healthy = healthy
            self.stateLabel = stateLabel
            self.scanned = scanned
            self.copies = copies
            self.areas = areas
            self.readsToday = readsToday
            self.grantUntil = grantUntil
            self.home = home
        }
    }

    public var facts: [String]
    public var state: State
    /// The home of the fact that needs the reader; nil when nothing does
    /// and there is no grant to look at.
    public var link: Home?

    public static func make(_ input: Input) -> AgentDigest {
        let key = keyFact(input)
        let copies = copiesFact(input)
        let reads = input.readsToday.map { $0 == 0 ? "no decoy reads today" : "\($0) decoy read" + ($0 == 1 ? "" : "s") + " today" }
            ?? "reads not checked yet"
        let grant = input.grantUntil.map { "grant until " + SessionState.clock($0) } ?? "no grant"

        var state = State.green
        var link: Home?
        if key.amber {
            state = .amber
            link = .tools
        }
        if copies.red {
            state = .red
            link = .findings
        }
        if link == nil, input.grantUntil != nil {
            link = .grants
        }
        return AgentDigest(facts: [key.text, copies.text, reads, grant], state: state, link: link)
    }

    private static func keyFact(_ input: Input) -> (text: String, amber: Bool) {
        switch input.key {
        case .protected:
            if input.wrapped, !input.healthy {
                return ("Key wrapped, but the " + input.stateLabel, true)
            }
            return ("Key wrapped", false)
        case let .found(source) where source.hasPrefix("~") || source.hasPrefix("/"):
            return ("Key in the open, " + ScanNotices.abbreviate(source, home: input.home), true)
        case .found:
            return ("Key in \(input.tool)'s own login, not in the vault", true)
        case .none:
            return ("No key on this Mac", false)
        case .unknown:
            return ("Key not checked yet", false)
        }
    }

    private static func copiesFact(_ input: Input) -> (text: String, red: Bool) {
        guard input.scanned else {
            return ("caches not searched yet", false)
        }
        guard input.copies > 0 else {
            return ("no cached copies", false)
        }
        let n = "\(input.copies) cached cop" + (input.copies == 1 ? "y" : "ies")
        return (n + " in its " + (input.areas.isEmpty ? "cache" : input.areas.joined(separator: " and ")), true)
    }
}
