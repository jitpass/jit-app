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
    /// The move the app started and jit may not have finished: kept across
    /// a relaunch, because jit's marker outlives the app.
    static let vaultKeyMovePendingKey = "vaultKeyMovePending"

    /// The saved preferences the row and Doctor's offer read.
    func loadVaultKeyPreferences() {
        let defaults = UserDefaults.standard
        model.vaultKeyOfferDismissed = defaults.bool(forKey: Self.vaultKeyOfferDismissedKey)
        model.vaultKeyMovePending = defaults.string(forKey: Self.vaultKeyMovePendingKey).flatMap(VaultKeyPlace.init(rawValue:))
    }

    private func setVaultKeyMovePending(_ place: VaultKeyPlace?) {
        model.vaultKeyMovePending = place
        if let place {
            UserDefaults.standard.set(place.rawValue, forKey: Self.vaultKeyMovePendingKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.vaultKeyMovePendingKey)
        }
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
        // A move this app started toward the same place and never saw end.
        let finishing = model.vaultKeyMovePending == target
        // A marker the app did not make (a move run in a terminal) is not
        // the app's to name: jit's refusal says which way it goes.
        if VaultKeyMove.markerPresent(model.doctor) != true || model.vaultKeyMovePending != nil {
            setVaultKeyMovePending(target)
        }
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
                if failure == nil, now == target {
                    setVaultKeyMovePending(nil)
                }
                settingsWindow.reclaimFocus()
                pollStatus()
                runDoctor()
            }
        }
    }

    /// A doctor report landed: the app's record of its move goes once jit
    /// has no marker (unless a move is running now), and a Restore pressed
    /// during the check runs now.
    func vaultKeyDoctorLanded() {
        if VaultKeyMove.settled(model.doctor), model.settingsApplying != .vaultKey {
            setVaultKeyMovePending(nil)
        }
        if model.vaultKeyRestoreQueued {
            model.vaultKeyRestoreQueued = false
            model.doctorMessage = nil
            if VaultKeyRow.keyLost(model.doctor) == false {
                model.doctorMessage = Format.restoreNotNeeded
            } else {
                restoreVaultKey()
            }
        }
    }

    /// The Settings row's Restore from Recovery File…: the lost key's own
    /// restore (`DoctorAdvice.restoreRecoveryFile`), run in the Doctor
    /// window, where its progress and how it ended are shown. It always
    /// says something: it runs, it waits for the check running now, or it
    /// says another action is in the way.
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
        let card = model.doctor.flatMap { report in
            DoctorBoard.make(report).cards.first { $0.items.contains(where: VaultKeyRow.isLostFinding) }
        }
        perform(
            [DoctorAdvice.restoreRecoveryFile],
            target: DoctorTarget(key: card?.id ?? "vault-key-restore", card: card, button: card?.primary)
        )
    }

    /// Doctor's ··· "Don't Suggest Again". Final: nothing brings the card
    /// back, and the Settings row still offers the move.
    func dismissVaultKeyOffer() {
        UserDefaults.standard.set(true, forKey: Self.vaultKeyOfferDismissedKey)
        model.vaultKeyOfferDismissed = true
    }
}
