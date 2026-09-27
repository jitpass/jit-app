// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Audit: the window and its reloads.
extension StatusItemController {
    var auditActions: AuditActions {
        AuditActions(
            setFilter: { [weak self] filter in
                guard let self, filter != model.auditFilter else {
                    return
                }
                model.auditFilter = filter
                reloadAudit()
            },
            openInTerminal: { [weak self] in self?.runInTerminal("jit audit") }
        )
    }

    // MARK: - Audit

    func openAudit(filter: AuditFilter? = nil) {
        panel.dismiss()
        if let filter {
            model.auditFilter = filter
        }
        auditWindow.present()
        reloadAudit()
    }

    /// Re-reads `jit audit` with the current filter, off the main thread.
    /// Called on open, on every filter change, and on every stream event
    /// while the window is showing, so the tail is never behind the CLI.
    /// A reload asked while one runs is kept and runs when it lands
    /// (`ReloadGate`), and a report read under a filter the user has since
    /// changed is not shown: the next read, under the chips on screen, is
    /// already starting.
    func reloadAudit() {
        guard auditGate.ask() else {
            return
        }
        readAudit()
    }

    private func readAudit() {
        model.auditLoading = true
        let filter = model.auditFilter
        Task.detached {
            let report = JitCLI.audit(filter)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                if filter == model.auditFilter {
                    model.audit = report?.addingLive(liveServes, filter: filter)
                }
                if auditGate.landed() {
                    readAudit()
                } else {
                    model.auditLoading = false
                }
            }
        }
    }
}
