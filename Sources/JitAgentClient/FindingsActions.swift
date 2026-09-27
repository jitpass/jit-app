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
    /// The kinds of the requests folded into this one besides `kind`. A
    /// merged run answers every one of them: it announces if any was
    /// scheduled, keeps the Protect banner if any followed a Protect, says
    /// its failure if any was by hand (review, 2026-09-27: "the later kind
    /// wins" dropped the others' meaning).
    public var also: Set<ScanRunKind>

    public init(wholeMac: Bool, kind: ScanRunKind, deep: Bool, also: Set<ScanRunKind> = []) {
        self.wholeMac = wholeMac
        self.kind = kind
        self.deep = deep
        self.also = also
    }

    /// Every kind this run answers.
    public var kinds: Set<ScanRunKind> {
        also.union([kind])
    }

    /// Two requests of the same scope waiting become one run that answers
    /// both: deep if either did, and the later request's kind, since it
    /// says who asked last — unless only the earlier one was deep, whose
    /// kind is what makes the run read the vault's report as its own.
    /// A folder and the whole Mac never merge (`ScanQueue`).
    public func merged(with later: ScanRequest) -> ScanRequest {
        let kind = deep && !later.deep ? kind : later.kind
        return ScanRequest(
            wholeMac: wholeMac,
            kind: kind,
            deep: deep || later.deep,
            also: kinds.union(later.kinds).subtracting([kind])
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

/// What a landed scan does to the Findings window, decided from the run
/// and what the window shows (`folderOnScreen`: the window is on a folder
/// of the user's choosing).
public struct ScanLanding: Equatable, Sendable {
    /// The report replaces the one on screen. A whole-Mac run never
    /// replaces a folder: it still feeds the panel and the other windows.
    public var showsReport: Bool
    /// A failure is said in the window. A scan the user started always is
    /// (a folder, or the whole Mac by hand or deep); a scheduled or
    /// follow-up run keeps the report it could not replace.
    public var saysFailure: Bool
    /// The folder on screen is scanned again: an action (Protect, Clean
    /// Caches, Undo) asked for this rescan, and a whole-Mac report does
    /// not replace the folder's, which would keep the rows the action just
    /// removed — and a second Protect would migrate them again
    /// (2026-09-27).
    public var rescansFolder: Bool

    public init(wholeMac: Bool, kind: ScanRunKind, folderOnScreen: Bool) {
        self.init(wholeMac: wholeMac, kinds: [kind], folderOnScreen: folderOnScreen)
    }

    /// For a merged run: each meaning holds if any of its kinds has it.
    public init(wholeMac: Bool, kinds: Set<ScanRunKind>, folderOnScreen: Bool) {
        showsReport = !wholeMac || !folderOnScreen
        saysFailure = !wholeMac || kinds.contains(where: \.isByHand)
        rescansFolder = wholeMac && folderOnScreen && kinds.contains(where: \.isAfterProtect)
    }

    /// The folder's rescan: regular, and the kind that keeps the action's
    /// banner up.
    public static let folderRescan = ScanRequest(wholeMac: false, kind: .afterProtect, deep: false)
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
