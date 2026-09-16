// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Grants: the New Grant sheet and `grant_create`.
extension StatusItemController {
    var grantActions: GrantActions {
        GrantActions(
            reloadProcesses: { [weak self] all in
                self?.model.grantProcesses = RunningProcesses.list(all: all)
                self?.model.grantProfiles = ProfileStore.globalNames()
                self?.model.brokenProfiles = self?.model.doctor?.brokenProfiles ?? JitCLI.doctor()?.brokenProfiles ?? [:]
            },
            grant: { [weak self] pid, profiles, ttl in self?.createGrant(pid: pid, profiles: profiles, ttl: ttl) },
            cancel: { [weak self] in self?.grantWindow.orderOut(nil) }
        )
    }

    // MARK: - Grants

    func openGrantSheet() {
        panel.dismiss()
        model.grantError = nil
        grantWindow.present()
    }

    /// One `grant_create`, off the main thread because the agent holds the
    /// call open while its Touch ID prompt is on screen.
    func createGrant(pid: Int32, profiles: [String], ttl: TimeInterval) {
        model.grantBusy = true
        model.grantError = nil
        let client = client
        Task.detached {
            let result = Result { try client.createGrant(pid: pid, profiles: profiles, projectRoot: nil, ttl: ttl) }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.grantBusy = false
                switch result {
                case .success:
                    grantWindow.orderOut(nil)
                    model.grants = (try? client.grants()) ?? []
                case let .failure(error):
                    model.grantError = Format.error(error)
                }
            }
        }
    }
}
