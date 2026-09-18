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
    func reloadAudit() {
        guard !model.auditLoading else {
            return
        }
        model.auditLoading = true
        let filter = model.auditFilter
        Task.detached {
            let report = JitCLI.audit(filter)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.audit = report?.addingLive(liveServes, filter: filter)
                model.auditLoading = false
            }
        }
    }
}
