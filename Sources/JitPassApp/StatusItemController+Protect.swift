// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// What one Protect ran: the migrate report (one for every file, one
/// plan, one Touch ID) and each wrap's text.
struct ProtectRun: Sendable {
    var reports: [MigrateReport] = []
    var wrapped: [String] = []
}

/// The Protect verb's shared pieces: the work off the main thread, the
/// banner's sentence from the reports' fields, and the Undo the banner
/// offers. Used by the Findings window's Protect (StatusItemController+Scan)
/// and the AI Agents window's Protect on an MCP config
/// (StatusItemController+Tools).
extension StatusItemController {
    /// Runs the plan: the vault first when this Mac has none, then one
    /// `jit migrate <files> --yes --format json`, then each `jit wrap`.
    /// A migrate that failed still returns its document with the partial
    /// result, which is what the banner must show.
    nonisolated static func protectWork(createsVault: Bool, migrate: [String], wraps: [String]) -> Result<ProtectRun, Error> {
        if createsVault, case let .failure(error) = JitCLI.execute(["vault", "init"]) {
            return .failure(error)
        }
        var run = ProtectRun()
        if !migrate.isEmpty {
            switch JitCLI.migrate(migrate) {
            case let .success(report): run.reports.append(report)
            case let .failure(error): return .failure(error)
            }
        }
        for tool in wraps {
            switch JitCLI.execute(["wrap", tool]) {
            case let .success(text): run.wrapped.append(text)
            case let .failure(error): return .failure(error)
            }
        }
        return .success(run)
    }

    /// The banner's sentence and jit's words, from the reports' fields:
    /// "Protected ~/notion/.env · NOTION_TOKEN is in the vault · 8 cached
    /// copies removed · 1 file left in Claude Code's transcripts · wrapped
    /// gh". Undo carries the files a migrate applied to.
    static func protectOutcome(_ reports: [MigrateReport], wrapped: [String], wraps: [String]) -> WindowOutcome {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var titles: [String] = []
        var failed = false
        var undo: [String] = []
        for report in reports {
            let outcome = ScanWording.protectOutcome(report, home: home)
            titles.append(outcome.title)
            failed = failed || outcome.failed
            if report.applied {
                undo += report.targets
            }
        }
        if !wrapped.isEmpty {
            let word = wraps.count == 1 ? "wrapped \(wraps[0])" : "wrapped \(wraps.count) tools"
            titles.append(titles.isEmpty ? word.prefix(1).uppercased() + word.dropFirst() : word)
        }
        let text = (reports.map(\.report) + wrapped).filter { !$0.isEmpty }.joined(separator: "\n\n")
        return WindowOutcome(title: titles.joined(separator: " · "), text: text, failed: failed, undo: undo)
    }

    /// `jit migrate undo <file> --yes` from the Findings banner: the file
    /// comes back from its encrypted backup, so its secret is plaintext on
    /// disk again — said before Touch ID. The cache copies the Protect
    /// removed stay removed; they have their own undo, named in jit's
    /// words.
    func undoProtect(_ paths: [String]) {
        guard !paths.isEmpty else {
            return
        }
        let alert = NSAlert()
        alert.messageText = paths.count == 1 ? "Undo protecting \(Format.home(paths[0]))?" : "Undo protecting \(paths.count) files?"
        alert.informativeText = (paths.count == 1 ? "The file is" : "Each file is")
            + " restored from its encrypted backup, so the secret is plaintext on disk again. "
            + "The cached copies the Protect removed stay removed. Touch ID follows."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        model.findingsOutcome = nil
        let title = paths.count == 1 ? "Restored \(Format.home(paths[0]))" : "Restored \(paths.count) files"
        runTools("undo", work: { JitCLI.execute(["migrate", "undo"] + paths + ["--yes"]) }, then: { [weak self] output in
            self?.model.scanStale = true
            self?.showResult(title: title, text: output)
            self?.runScan(wholeMac: true, kind: .afterProtect)
        })
    }
}
