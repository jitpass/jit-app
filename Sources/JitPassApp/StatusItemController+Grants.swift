// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Grants: the window, its New Grant sheet, `grant_create` and
/// `grant_revoke`. The app collects the request and renders the answer;
/// the service decides, and every op here is one the CLI can send.
extension StatusItemController {
    var grantActions: GrantActions {
        GrantActions(
            reload: { [weak self] in self?.reloadGrantSheet() },
            chooseFolder: { [weak self] in self?.chooseProfileFolder() },
            openFindings: { [weak self] in
                self?.model.grantSheet = false
                self?.openScan()
            },
            grant: { [weak self] draft in self?.createGrant(draft) },
            cancel: { [weak self] in
                self?.model.grantSheet = false
                self?.model.grantError = nil
                self?.model.grantPrefill = nil
                self?.model.grantReplacing = nil
            }
        )
    }

    var grantsActions: GrantsActions {
        GrantsActions(
            reload: { [weak self] in self?.reloadGrants() },
            newGrant: { [weak self] in self?.openGrantSheet() },
            revoke: { [weak self] grant in self?.confirmRevoke(grant) },
            reapprove: { [weak self] grant in self?.reapprove(grant) },
            fit: { [weak self] height in self?.grantsWindow.fit(to: height) }
        )
    }

    func openGrants() {
        panel.dismiss()
        reloadGrants()
        grantsWindow.present()
    }

    /// New Grant is the Grants window's sheet: the window opens first, then
    /// the sheet drops from its title bar. A prefill is a re-approval, which
    /// replaces `replacing` once the new grant lands.
    func openGrantSheet(prefill: GrantDraft? = nil, replacing: String? = nil) {
        panel.dismiss()
        model.grantBanner = nil
        model.grantError = nil
        model.grantPrefill = prefill
        model.grantReplacing = replacing
        reloadGrants()
        reloadGrantSheet()
        grantsWindow.present()
        model.grantSheet = true
    }

    func reloadGrants() {
        model.grants = (try? client.grants()) ?? []
    }

    /// Everything the sheet lists: the usual programs and every process,
    /// the apps to anchor under, and every profile jit can find from the
    /// registry, the programs' folders and the global store.
    func reloadGrantSheet() {
        model.grantProcesses = RunningProcesses.list(all: false)
        model.grantAllProcesses = RunningProcesses.list(all: true)
        model.grantSessionRoots = RunningProcesses.sessionRoots()
        let folders = model.grantAllProcesses.map { Format.expandHome($0.folder) }.filter { !$0.isEmpty }
        model.grantProfiles = ProfileStore.discover(workingDirectories: folders, extraRoots: model.grantExtraRoots)
        model.brokenProfiles = model.doctor?.brokenProfiles ?? JitCLI.doctor()?.brokenProfiles ?? [:]
        // The service refuses a grant naming any secret the vault lacks, so
        // every listed profile is checked against the vault's paths here,
        // prompt-free, and shown dimmed with the count rather than ticked
        // into a create that can only fail after Touch ID.
        if let listing = try? JitCLI.vaultList() {
            let held = Set(listing.secrets.map(\.path))
            var missing: [String: String] = [:]
            for profile in model.grantProfiles {
                let gone = profile.missing(from: held).count
                if gone > 0 {
                    missing[profile.manifestPath] = gone == 1
                        ? "1 of its secrets is not in the vault"
                        : "\(gone) of its secrets are not in the vault"
                }
            }
            model.grantMissing = missing
        }
    }

    /// One `grant_create`, off the main thread because the agent holds the
    /// call open while its Touch ID prompt is on screen.
    func createGrant(_ draft: GrantDraft) {
        guard draft.isComplete else {
            return
        }
        model.grantBusy = true
        model.grantError = nil
        let client = client
        let replacing = model.grantReplacing
        Task.detached {
            let result = Result { () throws -> GrantStatus in
                switch draft.cover {
                case .everyCopy:
                    guard let anchor = draft.anchorPID else {
                        throw AgentClientError.agent("no app chosen")
                    }
                    return try client.createTreeGrant(
                        anchorPID: anchor, name: draft.programName, profiles: draft.grantProfiles, ttl: draft.term.ttl
                    )
                case .oneProcess:
                    guard let pid = draft.pid, let ttl = draft.term.ttl else {
                        throw AgentClientError.agent("no process chosen")
                    }
                    return try client.createGrant(pid: pid, profiles: draft.grantProfiles, ttl: ttl)
                }
            }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.grantBusy = false
                switch result {
                case .success:
                    // A re-approval is a new grant; the one it replaces goes
                    // only once the new one exists, so a refused prompt
                    // leaves the old grant serving what it still can.
                    if let replacing {
                        try? client.revokeGrant(id: replacing)
                    }
                    model.grantReplacing = nil
                    model.grantPrefill = nil
                    model.grantSheet = false
                    reloadGrants()
                    grantsWindow.reclaimFocus()
                case let .failure(error):
                    model.grantError = Format.error(error)
                }
            }
        }
    }

    /// Revoke asks once, because a standing grant's revoke deletes a key.
    /// Revoke is the default button: nothing dangerous follows it, and
    /// reducing access is meant to stay the easiest thing in the window.
    func confirmRevoke(_ grant: GrantStatus) {
        let alert = NSAlert()
        alert.messageText = Format.revokeTitle(grant)
        alert.informativeText = Format.revokeMessage(grant)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Revoke")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        do {
            try client.revokeGrant(id: grant.id)
            model.grantBanner = Format.revokedBanner(grant)
            model.grantBannerFailed = false
        } catch {
            model.grantBanner = "Could not revoke \(Format.grantName(grant))'s grant: " + Format.error(error)
            model.grantBannerFailed = true
        }
        reloadGrants()
    }

    /// Re-approve: the sheet, filled with the grant as it was, so one Touch
    /// ID re-wraps every secret it covers, and the old grant is revoked
    /// once the new one exists.
    func reapprove(_ grant: GrantStatus) {
        reloadGrantSheet()
        let anchor = model.grantSessionRoots.first { $0.name == grant.anchor }
        let wanted = Set(grant.profileRoots ?? grant.profiles.map { GrantProfile(name: $0) })
        let profiles = model.grantProfiles.filter { wanted.contains($0.grantProfile) }
        let draft = GrantDraft(
            cover: .everyCopy, program: grant.name ?? "", anchorPID: anchor?.pid, anchorName: anchor?.name ?? grant.anchor,
            profiles: profiles, term: .untilRevoked
        )
        openGrantSheet(prefill: draft, replacing: grant.id)
    }

    /// A folder jit did not find on its own: added to the discovery roots
    /// for this session, never the first step.
    func chooseProfileFolder() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.prompt = "Add"
        picker.message = "Choose a project folder whose profiles jit did not find on its own."
        guard picker.runFrontmost() == .OK, let url = picker.url else {
            return
        }
        model.grantExtraRoots.append(url.path)
        reloadGrantSheet()
    }
}
