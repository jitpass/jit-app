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
            protect: { [weak self] command in self?.runInTerminal(command) },
            protectAll: { [weak self] commands in self?.runInTerminal(commands.joined(separator: "\n")) },
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
    func runScan() {
        guard !model.scanning else {
            return
        }
        model.scanning = true
        model.scanError = nil
        let scope = model.scanScope
        let excludes = model.scanExcludes
        Task.detached {
            let result = Result { try JitCLI.scan(path: scope, excludes: excludes) }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.scanning = false
                switch result {
                case let .success(report): model.scan = report
                case let .failure(error): model.scanError = "scan failed: \(error)"
                }
            }
        }
    }
}
