// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Scan: the report window, the folder picker, and running `jit scan`.
extension StatusItemController {
    var scanActions: ScanActions {
        ScanActions(
            rescan: { [weak self] in self?.runScan() },
            openSettings: { [weak self] in self?.openSettings() },
            chooseFolder: { [weak self] in self?.chooseScanFolder() },
            scanWholeMac: { [weak self] in
                self?.model.scanScope = nil
                self?.runScan()
            },
            openInTerminal: { [weak self] in self?.openScanInTerminal() },
            protect: { [weak self] command in
                self?.model.scanStale = true
                self?.runInTerminal(command)
            },
            protectAll: { [weak self] commands in
                self?.model.scanStale = true
                self?.runInTerminal(commands.joined(separator: "\n"))
            },
            open: { path, line in Editor.open(path, line: line) },
            reveal: { path in Editor.reveal(path) },
            grantFullDiskAccess: { FullDiskAccess.openSettings() }
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
        guard picker.runModal() == .OK, let url = picker.url else {
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
}
