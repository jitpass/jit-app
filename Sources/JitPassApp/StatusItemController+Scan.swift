// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Scan: the report window, the folder picker, and running `jit scan`.
extension StatusItemController {
    var scanActions: ScanActions {
        ScanActions(
            rescan: { [weak self] in self?.askDepth(scope: self?.model.scanScope) },
            newScan: { [weak self] in
                // Back to the chooser: the window's report is dropped, the
                // whole-Mac result the panel shows is not.
                self?.model.scan = nil
                self?.model.scanScope = nil
                self?.model.scanError = nil
            },
            openSettings: { [weak self] in self?.openSettings() },
            chooseFolder: { [weak self] in self?.chooseScanFolder() },
            scanWholeMac: { [weak self] in self?.askDepth(scope: nil) },
            protect: { [weak self] finding in
                if let tool = finding.wrapTool {
                    self?.protectPlan(ProtectPlan(wrap: [tool]))
                } else {
                    self?.protectPlan(ProtectPlan(migrate: [finding.filePath]))
                }
            },
            protectAll: { [weak self] plan in self?.protectPlan(plan) },
            closeSheet: { [weak self] in self?.model.scanSheet = nil },
            open: { path, line in Editor.open(path, line: line) },
            reveal: { path in Editor.reveal(path) },
            copyPath: { path in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            },
            showLines: { [weak self] group in self?.model.scanLines = group },
            grantFullDiskAccess: { FullDiskAccess.openSettings() },
            cleanCaches: { [weak self] in self?.cleanCaches() },
            undoProtect: { [weak self] paths in self?.undoProtect(paths) },
            showOutcome: { [weak self] outcome in self?.model.scanSheet = .result(title: outcome.title, text: outcome.text) },
            askDepth: { [weak self] scope in self?.askDepth(scope: scope) },
            startScan: { [weak self] scope, mode in self?.startScan(scope: scope, mode: mode) }
        )
    }

    // MARK: - Scan

    /// Opens the report. Nothing is scanned until the user chooses a scope
    /// in the window; a whole-home read is never a side effect of a click.
    func openScan() {
        panel.dismiss()
        model.fullDiskAccess = FullDiskAccess.granted()
        scanWindow.present()
        refreshScanIfDue()
    }

    // MARK: - Background scan

    /// How often the due check runs; the schedule itself decides whether
    /// anything happens, so this is only a granularity.
    static let scanCheckInterval: TimeInterval = 600

    /// A whole-Mac scan on the user's schedule (Settings), or sooner when
    /// a Protect just ran. Only with Full Disk Access: without it a scan
    /// raises a folder prompt per protected folder, and a prompt with no
    /// click behind it is exactly what the app must never cause.
    func refreshScanIfDue() {
        guard !model.scanning, model.fullDiskAccess || FullDiskAccess.granted() else {
            return
        }
        model.fullDiskAccess = true
        let due = model.scanSchedule.isDue(last: model.macScanAt) || (model.scanStale && model.scanSchedule != .off)
        guard due else {
            return
        }
        runScan(wholeMac: true, kind: model.scanStale ? .afterProtect : .scheduled)
    }

    /// The panel's Scan Now: the window, with the depth question up for
    /// the whole Mac. A click on a verb named "scan" is the one case where
    /// a whole-home read is not a side effect, and the sheet is where the
    /// depth is chosen every time.
    func scanNow() {
        openScan()
        askDepth(scope: nil)
    }

    /// Every scan the user starts passes through the depth sheet (design:
    /// frames 2 and 7). The schedule never does: it runs regular.
    func askDepth(scope: String?) {
        model.scanScope = scope
        model.scanSheet = .scanDepth(scope: scope)
    }

    /// The sheet's answer.
    func startScan(scope: String?, mode: ScanMode) {
        model.scanSheet = nil
        model.scanScope = scope
        runScan(wholeMac: scope == nil, kind: mode == .deep ? .deep : .byHand, deep: mode == .deep)
    }

    /// The standard folder picker; a choice limits the next scan to it,
    /// exactly as `jit scan <path>` would.
    func chooseScanFolder() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.prompt = "Scan"
        picker.message = "Choose a folder to scan for plaintext secrets."
        picker.directoryURL = model.scanScope.map { URL(fileURLWithPath: $0) }
        guard picker.runFrontmost() == .OK, let url = picker.url else {
            return
        }
        askDepth(scope: url.path)
    }

    /// Runs `jit scan` off the main thread and publishes the report. The
    /// scan is read-only and never prompts, which is what makes it safe to
    /// start from a click.
    ///
    /// `wholeMac` ignores the window's folder: a background run feeds the
    /// Protected row, and shows in the window only when the window is not
    /// looking at a folder of its own. `kind` is who asked, for the
    /// Findings header.
    func runScan(wholeMac: Bool = false, kind: ScanRunKind, deep: Bool = false) {
        guard !model.scanning else {
            return
        }
        model.scanning = true
        model.scanDeep = deep
        model.scanError = nil
        if kind != .afterProtect {
            model.findingsOutcome = nil // the banner clears on the next action; the rescan a Protect triggers is not one
        }
        let scope = wholeMac ? nil : model.scanScope
        let excludes = model.scanExcludes
        Task.detached {
            let result = Result { try JitCLI.scan(path: scope, excludes: excludes, deep: deep) }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.scanning = false
                switch result {
                case let .success(report):
                    if scope == nil {
                        let at = Date()
                        let fresh = rememberFindings(in: report)
                        model.macScan = report
                        model.macScanAt = at
                        model.macScanKind = kind
                        model.scanStale = false
                        if kind == .scheduled {
                            announceNewFindings(fresh, at: at)
                        }
                    }
                    if !wholeMac || model.scanScope == nil {
                        model.scan = report
                    }
                case let .failure(error):
                    if !wholeMac {
                        model.scanError = "scan failed: \(error)"
                    }
                }
            }
        }
    }

    /// What this whole-Mac scan has that the previous one did not, against
    /// the ids saved by the previous one, so a relaunch does not reset it.
    /// The very first scan only saves: there is nothing to compare with,
    /// and calling everything new would be noise. Returns the new findings
    /// for the notification.
    @discardableResult
    func rememberFindings(in report: ScanReport) -> [ScanFinding] {
        let defaults = UserDefaults.standard
        var fresh: [ScanFinding] = []
        if let known = defaults.stringArray(forKey: Notifier.knownFindingsKey) {
            fresh = report.newFindings(known: Set(known))
            model.macScanNew = Set(fresh.map(\.id))
            model.previousMacScanAt = defaults.object(forKey: Notifier.knownFindingsAtKey) as? Date
        } else {
            model.macScanNew = nil
            model.previousMacScanAt = nil
        }
        defaults.set(report.countedIDs, forKey: Notifier.knownFindingsKey)
        defaults.set(Date(), forKey: Notifier.knownFindingsAtKey)
        return fresh
    }

    // MARK: - Protect

    /// What the plan protects, one per line: the files by path and the
    /// tools by name. The dialog used to list its commands instead, and
    /// that block was the only place these names appeared, so it is the
    /// one command line whose removal had to put something back.
    static func protectedNames(_ plan: ProtectPlan) -> String {
        (plan.migrate.map(Format.home) + plan.wrap.map { "the \($0) command" }).joined(separator: "\n")
    }

    /// The scan window's Protect, in-app: one `jit migrate a b c --yes`
    /// for every file (one plan, one Touch ID), then `jit wrap <tool>` for
    /// each wrap finding, after a dialog that names what it protects. The
    /// output goes to a sheet, and the Mac is rescanned so the report and
    /// the panel row move together.
    func protectPlan(_ plan: ProtectPlan) {
        guard !plan.isEmpty else {
            return
        }
        guard vaultAllowsProtect() else {
            return
        }
        // A Mac that was never set up has no vault for migrate to write to:
        // Protect used to fail there. Creating it is part of the same,
        // named, confirmed plan.
        let createsVault = model.setup == .needsSetup
        // migrate sweeps the agent caches for copies of what it just vaulted.
        // The scan on screen already lists those copies, each with the file
        // it came from, so the dialog can say what the sweep will reach
        // before Touch ID — the fix for "Protect cleared my AI-cache
        // alerts" (design/scan-and-protect.md D7). No scan runs here.
        let copies = (model.scan ?? model.macScan)?.copies(from: plan.migrate) ?? []
        let sweep = ScanWording.sweepSentence(copies: copies).map { $0 + "\n\n" } ?? ""
        let alert = NSAlert()
        alert.messageText = plan.count == 1
            ? "Protect \(plan.migrate.first.map(Format.home) ?? plan.wrap.first ?? "")?"
            : "Protect \(plan.count) findings?"
        alert.informativeText = (createsVault ? "This Mac has no vault yet, so this creates one first. " : "")
            + "These move into the vault:\n\n\(Self.protectedNames(plan))\n\n"
            + sweep
            + "Each file is rewritten so what reads it keeps working, and is backed up encrypted first; "
            + "jit migrate undo restores it. Touch ID follows."
        alert.addButton(withTitle: "Protect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        model.findingsOutcome = nil
        // One migrate for every file (one plan, one Touch ID), as a report
        // the banner reads by its fields; then each wrap, whose output is
        // still text (StatusItemController+Protect).
        let migrate = plan.migrate
        let wraps = plan.wrap
        runTools("scan", work: { Self.protectWork(createsVault: createsVault, migrate: migrate, wraps: wraps) }, then: { [weak self] run in
            guard let self else {
                return
            }
            model.scanStale = true
            let outcome = Self.protectOutcome(run.reports, wrapped: run.wrapped, wraps: wraps)
            showResult(title: outcome.title, text: outcome.text, failed: outcome.failed, undo: outcome.undo)
            runScan(wholeMac: true, kind: .afterProtect)
        })
    }
}
