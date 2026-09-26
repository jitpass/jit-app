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
    static let vaultKeyOfferDismissedKey = "vaultKeyOfferDismissed"

    /// The saved preference Doctor's offer reads. Nothing about a move is
    /// saved: an unfinished one is jit's own `move_unfinished`.
    func loadVaultKeyPreferences() {
        model.vaultKeyOfferDismissed = UserDefaults.standard.bool(forKey: Self.vaultKeyOfferDismissedKey)
    }

    /// Sheet B or C, over Settings. Doctor's Move… comes here too, so the
    /// move happens where the way back is. Never for an empty vault: jit
    /// reports no recovery file for one, so Move Key could never open.
    func openVaultKeyMove() {
        guard model.settingsApplying == nil, model.canMoveVaultKeyIn else {
            return
        }
        openSettings()
        model.recoveryFileFailure = nil
        model.vaultKeySheet = true
    }

    /// "Save Recovery File…": the Vault window's export, its save panel and
    /// passphrase, returning to the sheet, which then reads jit's own record
    /// of it from `jit status`.
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
                if case let .failure(error) = result {
                    model.recoveryFileFailure = Self.describe(error)
                }
            }
        }
    }

    /// Move Key: the sheet closes, the row carries the wait.
    func confirmVaultKeyMove() {
        guard VaultKeySheetDefault.moveEnabled(model.recoveryFile, saving: model.recoveryFileSaving) else {
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

    /// The failure row's Try Again… and the unfinished row's Finish Move:
    /// the move that failed, never the opposite one, which jit refuses
    /// while a move is half done. A half-done move runs again as it is;
    /// one that changed nothing asks again (sheet C in, alert G back).
    func retryVaultKey() {
        guard let retry = model.vaultKeyRetry else {
            return
        }
        if retry.finishes {
            moveVaultKey(to: retry.target)
        } else if retry.target == .secureEnclave {
            openVaultKeyMove()
        } else {
            confirmMoveBack()
        }
    }

    /// One `jit vault rekey --wrapper …`, then jit is asked where the key
    /// is now, so the banner, the row and the failure's title say what is
    /// true rather than what was meant or what the exit code implied.
    private func moveVaultKey(to target: VaultKeyPlace) {
        guard model.settingsApplying == nil else {
            return
        }
        model.settingsApplying = .vaultKey
        model.settingsOutcome = nil
        let before = model.vaultKeyPlace
        // A move jit says stopped partway toward the same place.
        let finishing = model.vaultKeyUnfinished == target
        model.vaultKeyAttempted = target
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
                let now = VaultKeyPlace.of(status?.vault)
                let failure: String? = switch result {
                case .success: nil
                case let .failure(JitCLI.CLIError.failed(line)): line
                case .failure: "jit is not installed where the app can find it."
                }
                model.settingsOutcome = .vaultKeyMoveEnded(
                    to: target, before: before, now: now, finishing: finishing, failure: failure
                )
                settingsWindow.reclaimFocus()
                pollStatus()
                runDoctor()
            }
        }
    }

    /// "Check Again": after a failed move whose status read failed too,
    /// and on an enclave row whose doctor check could not run. jit is
    /// asked where the key is, and doctor runs again; with an answer the
    /// row shows it in place of the unknown result, and without one the
    /// unknown result stays.
    func checkVaultKeyAgain() {
        guard model.settingsApplying == nil else {
            return
        }
        Task.detached {
            JitCLI.forgetStatus()
            let status = JitCLI.status()
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                if let status {
                    model.cli = status
                    if model.settingsOutcome?.row == .vaultKey {
                        model.settingsOutcome = nil
                    }
                }
                runDoctor()
            }
        }
    }

    /// A doctor report landed: after a Doctor action on a vault key that
    /// is not well (an unfinished move, a restore), jit's status is read
    /// again so the Settings row follows; and a Restore pressed during the
    /// check runs now.
    func vaultKeyDoctorLanded(afterAction: Bool) {
        if afterAction, vaultKeyNeedsAttention {
            Task.detached {
                JitCLI.forgetStatus()
                let status = JitCLI.status()
                await MainActor.run { [weak self] in
                    if let self, let status {
                        model.cli = status
                    }
                }
            }
        }
        if model.vaultKeyRestoreQueued {
            model.vaultKeyRestoreQueued = false
            model.doctorMessage = nil
            if restoreKind == nil {
                model.doctorMessage = Format.restoreNotNeeded
            } else {
                restoreVaultKey()
            }
        }
    }

    /// The row is in a state a Doctor action can end.
    private var vaultKeyNeedsAttention: Bool {
        switch model.vaultKeyRow {
        case .lost, .unfinished, .restorePending, .restoreUnchecked, .changeUnknown: true
        default: false
        }
    }

    /// Which restore the vault needs: the lost key's (a new key, then the
    /// import), a pending one's (the key exists, the import alone), what
    /// jit names when it could not check, or none (`VaultKeyRow.restore`).
    private var restoreKind: (action: DoctorAction, finding: (DoctorItem) -> Bool)? {
        model.vaultKeyRestore
    }

    /// The Settings row's Restore from Recovery File…: the lost key's own
    /// restore (`DoctorAdvice.restoreRecoveryFile`), or the import alone
    /// for a restore jit still reports pending, run in the Doctor window,
    /// where its progress and how it ended are shown. It always says
    /// something: it runs, it waits for the check running now, or it says
    /// another action is in the way.
    func restoreVaultKey() {
        openDoctor()
        guard doctorIdle else {
            if model.doctorBusy == nil {
                model.vaultKeyRestoreQueued = true
                model.doctorMessage = Format.restoreQueued
            } else {
                model.doctorMessage = Format.restoreBusy
            }
            return
        }
        guard let restore = restoreKind else {
            model.doctorMessage = Format.restoreNotNeeded
            return
        }
        let card = model.doctor.flatMap { report in
            DoctorBoard.make(report).cards.first { $0.items.contains(where: restore.finding) }
        }
        perform(
            [restore.action],
            target: DoctorTarget(key: card?.id ?? "vault-key-restore", card: card, button: card?.primary)
        )
    }

    /// The red row's Doctor…: opens the window whose `vault_key_copy` card
    /// carries jit's own fix, Remove from Keychain. When the last check
    /// predates the key left behind (Settings reads it from `jit status`,
    /// Doctor from `jit doctor`), Doctor checks again so the card is there.
    func openDoctorForKeyCopy() {
        openDoctor()
        let hasCard = model.doctor.map { report in
            DoctorBoard.make(report).cards.contains { $0.items.contains { $0.kind == "vault_key_copy" } }
        } ?? false
        if !hasCard, doctorIdle {
            runDoctor()
        }
    }

    /// Doctor's ··· "Don't Suggest Again". Final: nothing brings the card
    /// back, and the Settings row still offers the move.
    func dismissVaultKeyOffer() {
        UserDefaults.standard.set(true, forKey: Self.vaultKeyOfferDismissedKey)
        model.vaultKeyOfferDismissed = true
    }
}
