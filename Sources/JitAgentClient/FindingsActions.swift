// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

public extension ScanWording {
    /// The Findings banner when an action's jit run failed outright: the
    /// verb and jit's own last line, said in the window that asked. Before
    /// this the line went to a message only the Tools and AI Agents windows
    /// show, so a Clean Caches that jit refused changed nothing and said
    /// nothing (2026-09-27).
    static func actionFailed(_ verb: String, line: String) -> String {
        let why = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(verb) failed · " + (why.isEmpty ? "jit did not say why" : why)
    }
}

/// A whole-Mac or folder scan someone asked for, kept while another scan
/// runs so it is not lost: the rescan a Clean Caches, Protect or Undo
/// asks for used to return early when a scan was already running, and the
/// window kept the rows the action had just removed.
public struct ScanRequest: Equatable, Sendable {
    public var wholeMac: Bool
    public var kind: ScanRunKind
    public var deep: Bool

    public init(wholeMac: Bool, kind: ScanRunKind, deep: Bool) {
        self.wholeMac = wholeMac
        self.kind = kind
        self.deep = deep
    }

    /// Two requests of the same scope waiting become one run that answers
    /// both: deep if either did, and the later request's kind, since it
    /// says who asked last — unless only the earlier one was deep, whose
    /// kind is what makes the run read the vault's report as its own.
    /// A folder and the whole Mac never merge (`ScanQueue`).
    public func merged(with later: ScanRequest) -> ScanRequest {
        ScanRequest(
            wholeMac: wholeMac,
            kind: deep && !later.deep ? kind : later.kind,
            deep: deep || later.deep
        )
    }
}

/// Scans asked for while another runs, none lost: one waiting folder scan
/// and one waiting whole-Mac scan, each folding the requests of its own
/// scope (`ScanRequest.merged`). The two never merge — a whole-Mac report
/// does not replace a folder on screen, so a folder scan widened to the
/// Mac would never be shown, and a deep one would read the vault for
/// every folder when the user chose one.
public struct ScanQueue: Equatable, Sendable {
    public private(set) var folder: ScanRequest?
    public private(set) var wholeMac: ScanRequest?

    public init() {}

    /// The request to start now, or nil when `running` and it waits.
    public mutating func ask(_ request: ScanRequest, running: Bool) -> ScanRequest? {
        guard running else {
            return request
        }
        if request.wholeMac {
            wholeMac = wholeMac.map { $0.merged(with: request) } ?? request
        } else {
            folder = folder.map { $0.merged(with: request) } ?? request
        }
        return nil
    }

    /// What to start once the running scan lands, taken off the queue:
    /// the folder first, since only a person picks one and the window is
    /// showing it; the whole Mac after, when that run lands.
    public mutating func next() -> ScanRequest? {
        if let request = folder {
            folder = nil
            return request
        }
        defer { wholeMac = nil }
        return wholeMac
    }
}

/// The window an action's result is said in. Decided when the action
/// starts, from the window the click came from: by the time jit answers,
/// the user may be in another window, or another app, after Touch ID.
public enum OutcomeWindow: Equatable, Sendable {
    case findings, decoys, agents, tools

    /// The window in front, by the rule `showResult` has always used:
    /// Findings, then Decoys, then AI Agents when it is key or open without
    /// Tools, else Tools.
    public static func front(
        findingsKey: Bool, decoysKey: Bool, agentsKey: Bool, agentsVisible: Bool, toolsVisible: Bool
    ) -> OutcomeWindow {
        if findingsKey {
            return .findings
        }
        if decoysKey {
            return .decoys
        }
        if agentsKey || (agentsVisible && !toolsVisible) {
            return .agents
        }
        return .tools
    }

    /// Only Findings and Decoys need the failure as their banner; AI
    /// Agents and Tools show `toolsMessage`, which every failure sets.
    public var needsFailureBanner: Bool {
        self == .findings || self == .decoys
    }
}
