// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What one Protect ran: the migrate report (one for every file, one
/// plan, one Touch ID), each wrap, and the wrap that failed. A wrap that
/// failed after migrate had applied used to throw the report away, so the
/// banner said "Protect failed" over files that were already in the vault,
/// with no Undo and no rescan (2026-09-27).
public struct ProtectRun: Sendable, Equatable {
    public var reports: [MigrateReport]
    /// The tools wrapped, in order.
    public var wrapped: [String]
    /// jit's text for each wrap, in the same order.
    public var wrappedText: [String]
    public var wrapFailure: WrapFailure?
    /// What the Protect sheet showed and the user confirmed, so What
    /// Changed can say per file what went to the vault and what stayed.
    /// Nil after the old question (an engine without `migrate preview`).
    public var split: ProtectSplit?

    /// The wrap jit refused, in its own words, and the ones after it that
    /// were not tried: a cancelled Touch ID is not asked again per tool.
    public struct WrapFailure: Sendable, Equatable {
        public var tool: String
        public var line: String
        public var notTried: [String]

        public init(tool: String, line: String, notTried: [String] = []) {
            self.tool = tool
            self.line = line
            self.notTried = notTried
        }
    }

    public init(reports: [MigrateReport] = [], wrapped: [String] = [], wrappedText: [String] = [], wrapFailure: WrapFailure? = nil) {
        self.reports = reports
        self.wrapped = wrapped
        self.wrappedText = wrappedText
        self.wrapFailure = wrapFailure
    }

    /// Something is already different: a migrate applied or a tool is
    /// wrapped. A wrap failing after that is part of the result, not the
    /// whole of it; before it, nothing changed and the failure is all.
    public var changedSomething: Bool {
        reports.contains(where: \.applied) || !wrapped.isEmpty
    }

    /// The files a migrate applied to, for Undo.
    public var undo: [String] {
        reports.filter(\.applied).flatMap(\.targets)
    }

    /// The files known to be in the vault now, so their rows may leave the
    /// report before the rescan. A report names its errors for the whole
    /// run, never per file, so one with any error beyond the agent-cache
    /// sweep (which leaves the files alone) vouches for none of its
    /// targets: the rescan decides those.
    public var protectedFiles: [String] {
        reports.filter { report in
            report.applied && report.errors.allSatisfy { $0.hasPrefix(Self.cacheSweepError) }
        }
        .flatMap(\.targets)
    }

    /// How jit words a failure of the sweep that runs after the files moved.
    static let cacheSweepError = "clearing AI agent caches: "
}

/// The banner after a Protect, from the run's fields.
public struct ProtectRunOutcome: Equatable, Sendable {
    public var title: String
    public var text: String
    public var failed: Bool
    public var undo: [String]
    public var changes: ChangeSheet
}

public extension ProtectRun {
    /// "Protected ~/acme/.env · ACME_TOKEN is in the vault · wrapped
    /// globex", or with a wrap refused, "… · wrap globex failed: <jit's
    /// line>". `home` is the user's home directory, so paths read `~/…`.
    func outcome(home: String) -> ProtectRunOutcome {
        var titles: [String] = []
        var failed = false
        for report in reports {
            let outcome = ScanWording.protectOutcome(report, home: home)
            titles.append(outcome.title)
            failed = failed || outcome.failed
        }
        if !wrapped.isEmpty {
            titles.append(wrapped.count == 1 ? "wrapped \(wrapped[0])" : "wrapped \(wrapped.count) tools")
        }
        if let wrapFailure {
            titles.append(ScanWording.wrapFailed(wrapFailure.tool, line: wrapFailure.line))
            failed = true
        }
        let text = (reports.map(\.report) + wrappedText + [wrapFailure?.line ?? ""])
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
        return ProtectRunOutcome(
            title: ScanWording.upperFirst(titles.joined(separator: " · ")),
            text: text,
            failed: failed,
            undo: undo,
            changes: ChangeSheet.protect(reports, wrapped: wrapped, wrapFailure: wrapFailure, report: text, split: split)
        )
    }
}

public extension ScanWording {
    /// "wrap globex failed: <jit's line>", a clause of the Protect banner.
    static func wrapFailed(_ tool: String, line: String) -> String {
        let why = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return "wrap \(tool) failed: " + (why.isEmpty ? "jit did not say why" : why)
    }

    /// The banner's first letter upper case: a line that starts with a
    /// clause ("wrapped globex") still reads as a sentence.
    static func upperFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
