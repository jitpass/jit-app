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
}
