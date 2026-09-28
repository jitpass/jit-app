// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient

extension StatusItemController {
    /// Who uses each secret, found in any project folder: a search of home,
    /// so off the main thread, after the listing is already on screen.
    /// One walk at a time: reloads that land while one runs fold into a
    /// single rerun after it, so an older walk never lands on a newer one.
    func refreshVaultUsers() {
        guard model.vaultUsersRun.ask() else {
            return
        }
        Task.detached {
            let users = JitCLI.vaultUsers()
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                if let users {
                    model.vaultUsers = users
                }
                if model.vaultUsersRun.finished() {
                    refreshVaultUsers()
                }
            }
        }
    }

    /// The cleanup: every entry protected before settings stayed plain,
    /// read with one Touch ID, and the settings among them moved out.
    func checkSettings() {
        runVault(VaultCommandLabel.settingsCheck, work: { JitCLI.migrateSettings() }, then: { [weak self] result in
            self?.model.vaultSheet = nil
            self?.model.settingsCheck = nil
            self?.notice(Format.checkedSettings(result))
        })
    }

    /// The first step: read every entry, move nothing, and let the sheet
    /// say which would move before anything does.
    func previewSettings() {
        runVault(
            VaultCommandLabel.settingsCheck,
            refresh: false,
            work: { JitCLI.migrateSettings(dryRun: true) },
            then: { [weak self] result in
                self?.model.settingsCheck = result
            }
        )
    }
}
