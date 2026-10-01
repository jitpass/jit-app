// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The Decoys window's wiring: the service's mount list (status), the
/// vault listing (names only, no prompt), the week's serve events (read
/// counts look at the last 24 hours of them), and the last scan. Its verbs are Findings' Protect and a file picker.
extension StatusItemController {
    func openDecoys() {
        panel.dismiss()
        model.decoysOutcome = nil
        reloadDecoys()
        decoysWindow.present()
    }

    /// Prompt-free reads, off the main thread: status for the files, the
    /// vault's names for their secret counts, the audit for the reads.
    func reloadDecoys() {
        loadDecoyExpected()
        let filter = AuditFilter(kinds: ["serve"], since: "7d", limit: 0)
        Task.detached {
            let status = JitCLI.status()
            let listing = try? JitCLI.vaultList()
            let audit = JitCLI.audit(filter)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                if let status {
                    model.cli = status
                }
                if let listing {
                    model.vaultListing = listing
                }
                if let audit {
                    model.decoyEvents = audit.addingLive(liveServes, filter: filter).authEvents.filter { $0.kind == "serve" }
                }
            }
        }
    }

    var decoysActions: DecoysActions {
        DecoysActions(
            reload: { [weak self] in self?.reloadDecoys() },
            closeSheet: { [weak self] in self?.model.decoysSheet = nil },
            // The rows of what changed: the same sheet Findings opens for
            // the same run.
            showOutcome: { [weak self] outcome in
                self?.model.decoysSheet = outcome.changes.map { .changes($0) }
            },
            open: { path, line in Editor.open(path, line: line) },
            reveal: { path in Editor.reveal(path) },
            copyPath: { path in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            },
            undoProtect: { [weak self] paths in self?.undoProtect(paths) },
            verify: { [weak self] tool in self?.verifyTool(tool) },
            protectAgain: { [weak self] paths in self?.protectFiles(paths) },
            openVault: { [weak self] in self?.openVault() },
            openScan: { [weak self] in self?.openScan() },
            openAudit: { [weak self] in self?.openAudit(filter: AuditFilter(kinds: ["serve"], since: "24h", limit: 0)) },
            protect: { [weak self] finding in
                if let tool = finding.wrapTool {
                    self?.protectPlan(ProtectPlan(wrap: [tool]))
                } else {
                    self?.protectPlan(ProtectPlan(migrate: [finding.filePath]))
                }
            },
            protectAll: { [weak self] plan in self?.protectPlan(plan) },
            protectAnother: { [weak self] in self?.protectAnotherFile() },
            askExpected: { [weak self] burst in self?.model.decoyExpectAsk = burst },
            closeExpected: { [weak self] in self?.model.decoyExpectAsk = nil },
            setExpected: { [weak self] reader, remove in self?.setDecoyExpected(reader, remove: remove) }
        )
    }

    /// The standard file picker, then the same migrate Findings runs on a
    /// row: for a credentials file the scan did not list.
    func protectAnotherFile() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = false
        picker.canChooseFiles = true
        picker.allowsMultipleSelection = false
        picker.showsHiddenFiles = true
        picker.prompt = "Protect"
        picker.message = "Choose a .env or credentials file. Its values move into the vault and a decoy takes its place."
        guard picker.runFrontmost() == .OK, let url = picker.url else {
            return
        }
        protectFile(url.path)
    }
}
