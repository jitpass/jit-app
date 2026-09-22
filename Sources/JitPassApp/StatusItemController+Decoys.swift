// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The Decoys window's wiring: the service's mount list (status), the
/// vault listing (names only, no prompt), the week's serve events, and
/// the last scan. Its verbs are Findings' Protect and a file picker.
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
            showOutcome: { [weak self] outcome in self?.model.decoysSheet = .result(title: outcome.title, text: outcome.text) },
            open: { path, line in Editor.open(path, line: line) },
            reveal: { path in Editor.reveal(path) },
            openVault: { [weak self] in self?.openVault() },
            openScan: { [weak self] in self?.openScan() },
            openAudit: { [weak self] in self?.openAudit(filter: AuditFilter(kinds: ["serve"], since: "7d")) },
            protect: { [weak self] finding in
                if let tool = finding.wrapTool {
                    self?.protectPlan(ProtectPlan(wrap: [tool]))
                } else {
                    self?.protectPlan(ProtectPlan(migrate: [finding.filePath]))
                }
            },
            protectAll: { [weak self] plan in self?.protectPlan(plan) },
            protectAnother: { [weak self] in self?.protectAnotherFile() }
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
