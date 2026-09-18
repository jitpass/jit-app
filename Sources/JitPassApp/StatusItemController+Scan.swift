// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Scan: the report window, the folder picker, and running `jit scan`.
extension StatusItemController {
    var scanActions: ScanActions {
        ScanActions(
            rescan: { [weak self] in self?.runScan() },
            newScan: { [weak self] in
                // Back to the chooser: the window's report is dropped, the
                // whole-Mac result the panel shows is not.
                self?.model.scan = nil
                self?.model.scanScope = nil
                self?.model.scanError = nil
            },
            openSettings: { [weak self] in self?.openSettings() },
            chooseFolder: { [weak self] in self?.chooseScanFolder() },
            scanWholeMac: { [weak self] in
                self?.model.scanScope = nil
                self?.runScan()
            },
            openInTerminal: { [weak self] in self?.openScanInTerminal() },
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
            grantFullDiskAccess: { FullDiskAccess.openSettings() },
            cleanCaches: { [weak self] in self?.cleanCaches() }
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
        runScan(wholeMac: true)
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
        model.scanScope = url.path
        runScan()
    }

    func openScanInTerminal() {
        let scope = model.scanScope.map { " " + Terminal.quoted($0) } ?? ""
        runInTerminal("jit scan --full" + scope)
    }

    /// Runs `jit scan` off the main thread and publishes the report. The
    /// scan is read-only and never prompts, which is what makes it safe to
    /// start from a click.
    ///
    /// `wholeMac` ignores the window's folder: a background run feeds the
    /// Protected row, and shows in the window only when the window is not
    /// looking at a folder of its own.
    func runScan(wholeMac: Bool = false) {
        guard !model.scanning else {
            return
        }
        model.scanning = true
        model.scanError = nil
        let scope = wholeMac ? nil : model.scanScope
        let excludes = model.scanExcludes
        Task.detached {
            let result = Result { try JitCLI.scan(path: scope, excludes: excludes) }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.scanning = false
                switch result {
                case let .success(report):
                    if scope == nil {
                        noteNewCachedCopies(in: report, since: model.macScan)
                        model.macScan = report
                        model.macScanAt = Date()
                        model.scanStale = false
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

    // MARK: - Protect

    /// The scan window's Protect, in-app: one `jit migrate a b c --yes`
    /// for every file (one plan, one Touch ID), then `jit wrap <tool>` for
    /// each wrap finding, after a dialog that names the commands. The
    /// output goes to a sheet, and the Mac is rescanned so the report and
    /// the panel row move together.
    func protectPlan(_ plan: ProtectPlan) {
        guard !plan.isEmpty else {
            return
        }
        guard vaultAllowsProtect() else {
            return
        }
        var commands: [[String]] = []
        // A Mac that was never set up has no vault for migrate to write to:
        // Protect used to fail there. Creating it is part of the same,
        // named, confirmed plan.
        let createsVault = model.setup == .needsSetup
        if createsVault {
            commands.append(["vault", "init"])
        }
        if !plan.migrate.isEmpty {
            commands.append(["migrate"] + plan.migrate + ["--yes"])
        }
        for tool in plan.wrap {
            commands.append(["wrap", tool])
        }
        let shown = commands.map { "jit " + $0.map(Format.home).joined(separator: " ") }.joined(separator: "\n")
        let alert = NSAlert()
        alert.messageText = plan.count == 1
            ? "Protect \(plan.migrate.first.map(Format.home) ?? plan.wrap.first ?? "")?"
            : "Protect \(plan.count) findings?"
        alert.informativeText = (createsVault ? "This Mac has no vault yet, so this creates one first. " : "")
            + "This runs:\n\n\(shown)\n\n"
            + "The secrets move into the vault and each file is rewritten so what reads it keeps working. "
            + "Every file is backed up encrypted first; jit migrate undo restores it. Touch ID follows."
        alert.addButton(withTitle: "Protect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        let work: @Sendable () -> Result<String, Error> = {
            var log: [String] = []
            for command in commands {
                switch JitCLI.execute(command) {
                case let .success(text): log.append(text)
                case let .failure(error): return .failure(error)
                }
            }
            return .success(log.joined(separator: "\n\n"))
        }
        let title = plan.count == 1 ? "Protected" : "Protected \(plan.count) findings"
        runTools("scan", work: work, then: { [weak self] output in
            self?.model.scanStale = true
            self?.showResult(title: title, text: output)
            self?.runScan(wholeMac: true)
        })
    }
}
