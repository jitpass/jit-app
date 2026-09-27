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

    /// Two requests waiting become one run that answers both: the whole
    /// Mac if either asked for it, deep if either did, and the later
    /// request's kind, since it says who asked last — unless only the
    /// earlier one was deep, whose kind is what makes the run read the
    /// vault's report as its own.
    public func merged(with later: ScanRequest) -> ScanRequest {
        ScanRequest(
            wholeMac: wholeMac || later.wholeMac,
            kind: deep && !later.deep ? kind : later.kind,
            deep: deep || later.deep
        )
    }
}

/// At most one scan waits behind the running one; every request made while
/// a scan runs folds into it (`ScanRequest.merged`), and none is lost.
public struct ScanQueue: Equatable, Sendable {
    public private(set) var waiting: ScanRequest?

    public init() {}

    /// The request to start now, or nil when `running` and it waits.
    public mutating func ask(_ request: ScanRequest, running: Bool) -> ScanRequest? {
        guard running else {
            return request
        }
        waiting = waiting.map { $0.merged(with: request) } ?? request
        return nil
    }

    /// What to start once the running scan lands, emptying the queue.
    public mutating func next() -> ScanRequest? {
        defer { waiting = nil }
        return waiting
    }
}
