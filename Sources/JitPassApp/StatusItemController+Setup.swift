// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// A Mac with no vault, and one with no service: the states a new user
/// starts in (docs/design/onboarding.md). Every step is a jit command the
/// CLI's own first run uses.
extension StatusItemController {
    /// "Start Service" with no service answering. The `unlock` op has no
    /// socket to go to; the panel used to send it anyway and drop the
    /// error, so on a Mac whose service was never installed the button did
    /// nothing. `jit unlock` is the CLI's "get me a session": it installs
    /// and starts the service first, then unlocks.
    func startService() {
        Task.detached {
            let result = JitCLI.execute(["unlock"])
            await MainActor.run { [weak self] in
                if case let .failure(error) = result {
                    // No window is open to hang a sheet on: the click came
                    // from the panel, which is already gone.
                    let alert = NSAlert()
                    alert.messageText = "The service did not start"
                    alert.informativeText = Self.describeTools(error)
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
                self?.pollStatus()
            }
        }
    }

    func continueSetup() {
        openOnboarding()
    }

    func setUpInTerminal() {
        UserDefaults.standard.set(true, forKey: MenuModel.terminalSetupKey)
        model.terminalSetup = true
        render()
    }

    /// Reads the vault state fresh (the cached status may predate a
    /// `jit vault init` run a moment ago, here or in a terminal) and says
    /// whether a Protect may go on. Secrets on disk with no key stop it: a
    /// new key would not open them and migrate would fail after the
    /// dialog, so the answer is a recovery file.
    func vaultAllowsProtect() -> Bool {
        JitCLI.forgetStatus()
        model.cli = JitCLI.status()
        guard model.setup == .needsRestore else {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "This Mac has a vault it cannot open"
        alert.informativeText = "Secrets are stored here, but the key that opens them is not in this Mac’s keychain. "
            + "A recovery file and its passphrase bring them back."
        alert.addButton(withTitle: "Restore…")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            openOnboarding()
        }
        return false
    }
}
