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
                self?.model.grantSessionRoots = RunningProcesses.sessionRoots()
                self?.model.grantProfiles = ProfileStore.globalNames()
                self?.model.brokenProfiles = self?.model.doctor?.brokenProfiles ?? JitCLI.doctor()?.brokenProfiles ?? [:]
            },
            grant: { [weak self] pid, profiles, ttl in
                self?.createGrant(profiles: profiles, ttl: ttl) { try $0.createGrant(
                    pid: pid,
                    profiles: profiles,
                    projectRoot: nil,
                    ttl: ttl
                ) }
            },
            grantTree: { [weak self] anchor, name, profiles, ttl in
                self?.createGrant(profiles: profiles, ttl: ttl) {
                    try $0.createTreeGrant(anchorPID: anchor, name: name, profiles: profiles, projectRoot: nil, ttl: ttl)
                }
            },
            cancel: { [weak self] in self?.grantWindow.orderOut(nil) }
        )
    }

    var grantsActions: GrantsActions {
        GrantsActions(
            revoke: { [weak self] id in self?.revokeGrant(id) },
            newGrant: { [weak self] in self?.openGrantSheet() },
            openInTerminal: { [weak self] in self?.runInTerminal("jit grant list") }
        )
    }

    func openGrants() {
        panel.dismiss()
        model.grants = (try? client.grants()) ?? []
        grantsWindow.present()
    }

    // MARK: - Grants

    func openGrantSheet() {
        panel.dismiss()
        model.grantError = nil
        grantWindow.present()
    }

    /// One `grant_create`, off the main thread because the agent holds the
    /// call open while its Touch ID prompt is on screen. `make` is the
    /// exact-process or tree variant.
    func createGrant(profiles _: [String], ttl _: TimeInterval, make: @escaping @Sendable (AgentClient) throws -> GrantStatus) {
        model.grantBusy = true
        model.grantError = nil
        let client = client
        Task.detached {
            let result = Result { try make(client) }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.grantBusy = false
                switch result {
                case .success:
                    grantWindow.orderOut(nil)
                    model.grants = (try? client.grants()) ?? []
                    runDoctor()
                case let .failure(error):
                    model.grantError = Format.error(error)
                }
            }
        }
    }

    func revokeGrant(_ id: String) {
        try? client.revokeGrant(id: id)
        model.grants = (try? client.grants()) ?? []
    }
}
