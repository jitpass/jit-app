// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient

extension StatusItemController {
    /// Who uses each secret, found in any project folder: a search of home,
    /// so off the main thread, after the listing is already on screen.
    func refreshVaultUsers() {
        Task.detached {
            let users = JitCLI.vaultUsers()
            await MainActor.run { [weak self] in
                if let users {
                    self?.model.vaultUsers = users
                }
            }
        }
    }

    /// The cleanup: every entry protected before settings stayed plain,
    /// read with one Touch ID, and the settings among them moved out.
    func checkSettings() {
        runVault("the old profiles", work: { JitCLI.migrateSettings() }, then: { [weak self] result in
            self?.model.vaultSheet = nil
            self?.model.settingsCheck = nil
            self?.notice(Format.checkedSettings(result))
        })
    }

    /// The first step: read every entry, move nothing, and let the sheet
    /// say which would move before anything does.
    func previewSettings() {
        runVault("the old profiles", refresh: false, work: { JitCLI.migrateSettings(dryRun: true) }, then: { [weak self] result in
            self?.model.settingsCheck = result
        })
    }
}
