// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit

/// What each row and button of the menu bar panel does: one closure per
/// row, each one call into the controller. Moved out of the class body
/// unchanged, to keep that body inside its length limit.
extension StatusItemController {
    var panelActions: PanelActions {
        PanelActions(
            lock: { [weak self] in self?.lockNow() },
            unlock: { [weak self] in self?.unlockNow() },
            openGrants: { [weak self] in self?.openGrants() },
            openAIJobs: { [weak self] in self?.openAIJobs() },
            openVault: { [weak self] in self?.openVault() },
            openTools: { [weak self] in self?.openTools() },
            openAgents: { [weak self] in self?.openAgents() },
            newGrant: { [weak self] in self?.openGrantSheet() },
            runScan: { [weak self] in self?.scanNow() },
            openScan: { [weak self] in self?.openScan() },
            openDoctor: { [weak self] in self?.openDoctor() },
            openAudit: { [weak self] in self?.openAudit() },
            openDecoys: { [weak self] in self?.openDecoys() },
            openSettings: { [weak self] in self?.openSettings() },
            openConsent: { [weak self] in self?.openConsent() },
            about: { [weak self] in self?.showAbout() },
            installUpdate: { [weak self] in self?.installUpdate() },
            continueSetup: { [weak self] in self?.continueSetup() },
            setUpInTerminal: { [weak self] in self?.setUpInTerminal() },
            quit: { NSApp.terminate(nil) }
        )
    }
}
