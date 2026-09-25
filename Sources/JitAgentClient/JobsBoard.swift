// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What the AI Jobs window shows, decided here where it is tested and not in
/// the view: which jobs stopped and need the human, which are ready, and how
/// many things wait (stopped jobs plus agents' proposals). The window's words
/// live in the app's Format; this only sorts.
public struct JobsBoard: Sendable, Equatable {
    public var stopped: [JobStatus]
    public var ready: [JobStatus]
    public var proposals: [JobProposal]

    public init(jobs: [JobStatus], proposals: [JobProposal] = []) {
        let sorted = jobs.sorted { $0.name < $1.name }
        stopped = sorted.filter { $0.jobState != .ready }
        ready = sorted.filter { $0.jobState == .ready }
        self.proposals = proposals.sorted { $0.unixTime < $1.unixTime }
    }

    public var isEmpty: Bool {
        stopped.isEmpty && ready.isEmpty
    }

    public var jobCount: Int {
        stopped.count + ready.count
    }

    /// Stopped jobs and waiting proposals: each is something only the human
    /// can answer.
    public var needsYou: Int {
        stopped.count + proposals.count
    }

    /// Every run since each job was approved.
    public var runs: Int64 {
        (stopped + ready).reduce(0) { $0 + ($1.runs ?? 0) }
    }
}

public extension PanelValue {
    /// The AI Jobs row. Nil, so no row at all, on a Mac that has never used
    /// AI Jobs: no job, no proposal, no app connected. Amber for anything
    /// waiting on the human; otherwise how many are ready.
    static func aiJobs(_ board: JobsBoard, connected: Bool) -> Row? {
        if board.isEmpty, board.proposals.isEmpty, !connected {
            return nil
        }
        if board.needsYou > 0 {
            return Row(needsYou(board.needsYou), .amber)
        }
        return board.isEmpty ? Row("none") : Row("\(board.ready.count) ready")
    }
}

/// `jit mcp status --format json`: whether an AI app starts jit's MCP server.
public struct MCPStatus: Codable, Sendable, Equatable {
    public var client: String
    public var config: String?
    public var installed: Bool
    public var command: String?
    /// The entry's jit exists and is executable.
    public var runnable: Bool

    public init(client: String, installed: Bool, command: String? = nil, runnable: Bool = false) {
        self.client = client
        self.installed = installed
        self.command = command
        self.runnable = runnable
    }

    /// Connected and able to start: what "Connected" may truthfully say.
    public var isConnected: Bool {
        installed && runnable
    }
}

/// The AI apps `jit mcp install` can connect, mirrored from jit's own table
/// (internal/cli/mcp.go, `mcpClients`): the id is its `--client` value.
public enum MCPApp: String, CaseIterable, Sendable, Identifiable {
    case claudeDesktop = "claude-desktop"
    case cursor

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .claudeDesktop: "Claude Desktop"
        case .cursor: "Cursor"
        }
    }

    /// Where the app is installed, which is when its row is shown.
    public var appPath: String {
        switch self {
        case .claudeDesktop: "/Applications/Claude.app"
        case .cursor: "/Applications/Cursor.app"
        }
    }

    /// How its agent reaches the jobs, for the connected row.
    public var via: String {
        switch self {
        case .claudeDesktop: "Cowork asks through jit mcp"
        case .cursor: "its agent asks through jit mcp"
        }
    }

    /// The `jit mcp` arguments that connect, disconnect or read it.
    public func arguments(_ verb: String) -> [String] {
        ["mcp", verb, "--client", rawValue]
    }
}
