// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Moving the vault key between the login keychain and the Secure Enclave:
/// `jit vault rekey --wrapper secure-enclave|keychain --yes`, run the way
/// every Settings command that asks for Touch ID runs (`JitCLI.apply`, off
/// the main thread), after the app's own sheet or alert has asked what
/// jit's y/N would. The spinner and the outcome land on the Protection
/// card's Vault key row; success is the window's banner.
extension StatusItemController {
    /// Where the app keeps the count jit said a recovery file holds, next
    /// to jit's own record of when it was saved.
    static let recoveryFileKey = "recoveryFileExport"
    static let vaultKeyOfferDismissedKey = "vaultKeyOfferDismissed"

    /// The saved preferences the row and Doctor's offer read.
    func loadVaultKeyPreferences() {
        let defaults = UserDefaults.standard
        model.vaultKeyOfferDismissed = defaults.bool(forKey: Self.vaultKeyOfferDismissedKey)
        model.recoveryFileRecorded = defaults.data(forKey: Self.recoveryFileKey)
            .flatMap { try? JSONDecoder().decode(RecordedExport.self, from: $0) }
    }

    /// Sheet B or C, over Settings. Doctor's Move… comes here too, so the
    /// move happens where its promise says it can be undone.
    func openVaultKeyMove() {
        guard model.settingsApplying == nil else {
            return
        }
        openSettings()
        model.recoveryFileFailure = nil
        model.vaultKeySheet = true
    }

    /// "Save Recovery File…": the Vault window's export, its save panel and
    /// passphrase, returning to the sheet. jit's closing line carries the
    /// count, kept beside jit's own record of the time.
    func saveRecoveryFile() {
        guard !model.recoveryFileSaving, let (path, passphrase) = askExport() else {
            return
        }
        model.recoveryFileSaving = true
        model.recoveryFileFailure = nil
        Task.detached {
            let result = JitCLI.execute(["vault", "export", path, "--stdin"], stdin: passphrase)
            JitCLI.forgetStatus()
            let status = JitCLI.status()
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.recoveryFileSaving = false
                model.cli = status ?? model.cli
                switch result {
                case let .success(output):
                    recordExport(output, status: status)
                case let .failure(error):
                    model.recoveryFileFailure = Self.describe(error)
                }
            }
        }
    }

    private func recordExport(_ output: String, status: CLIStatus?) {
        guard let count = RecordedExport.count(in: output), let unix = status?.vault?.exportUnixTime else {
            return
        }
        let recorded = RecordedExport(unixTime: unix, secrets: count)
        model.recoveryFileRecorded = recorded
        if let data = try? JSONEncoder().encode(recorded) {
            UserDefaults.standard.set(data, forKey: Self.recoveryFileKey)
        }
    }

    /// Move Key: the sheet closes, the row carries the wait.
    func confirmVaultKeyMove() {
        guard model.recoveryFile.ready else {
            return
        }
        model.vaultKeySheet = false
        moveVaultKey(to: .secureEnclave)
    }

    /// Frame G: an alert, since there is nothing to read but the question.
    /// It lowers protection, so Cancel is the default and Return cancels.
    func confirmMoveBack() {
        guard model.settingsApplying == nil else {
            return
        }
        let alert = NSAlert()
        alert.messageText = Format.moveBackTitle
        alert.informativeText = Format.moveBackMessage
        alert.alertStyle = .informational
        let cancel = alert.addButton(withTitle: "Cancel")
        let move = alert.addButton(withTitle: "Move Back")
        cancel.keyEquivalent = "\r"
        move.keyEquivalent = ""
        guard alert.runFrontmost() == .alertSecondButtonReturn else {
            return
        }
        moveVaultKey(to: .keychain)
    }

    /// The failure row's Try Again…: the same question again, for the way
    /// the key was going (sheet C in, alert G back).
    func retryVaultKey() {
        switch model.vaultKeyRow {
        case .secureEnclave: confirmMoveBack()
        default: openVaultKeyMove()
        }
    }

    /// One `jit vault rekey --wrapper …`, then jit is asked where the key
    /// is now, so the row and the failure's title say what is true rather
    /// than what was meant.
    private func moveVaultKey(to target: VaultKeyPlace) {
        guard model.settingsApplying == nil else {
            return
        }
        model.settingsApplying = .vaultKey
        model.settingsOutcome = nil
        let recorded = model.recoveryFileRecorded
        Task.detached {
            let result = JitCLI.apply(target.moveArguments)
            JitCLI.forgetStatus()
            let status = JitCLI.status()
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.settingsApplying = nil
                model.cli = status ?? model.cli
                let now = status?.vault?.keyStore.flatMap(VaultKeyPlace.init(rawValue:))
                switch result {
                case .success:
                    model.settingsOutcome = .vaultKeyMoved(to: target)
                case let .failure(JitCLI.CLIError.failed(line)):
                    let behind = RecoveryFile.newSecrets(status?.vault, recorded: recorded)
                    model.settingsOutcome = .vaultKeyFailed(to: target, now: now, line: line, newSecrets: behind)
                case .failure:
                    model.settingsOutcome = .vaultKeyFailed(
                        to: target, now: now, line: "jit is not installed where the app can find it."
                    )
                }
                settingsWindow.reclaimFocus()
                pollStatus()
                runDoctor()
            }
        }
    }

    /// Doctor's ··· "Don't Suggest Again". The Settings row still offers
    /// the move.
    func dismissVaultKeyOffer() {
        UserDefaults.standard.set(true, forKey: Self.vaultKeyOfferDismissedKey)
        model.vaultKeyOfferDismissed = true
    }
}
