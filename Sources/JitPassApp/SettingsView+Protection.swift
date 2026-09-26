// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Protection segment: what jit hands out and when it asks. One card,
/// so no eyebrow; the restart each change costs is on its own row.
extension SettingsView {
    static let ttls: [(label: String, value: String)] = [
        ("5 minutes", "5m"), ("15 minutes", "15m"), ("30 minutes", "30m"), ("1 hour", "1h"),
        ("2 hours", "2h"), ("4 hours", "4h"), ("8 hours", "8h")
    ]

    var protectionCard: some View {
        AppPlainCard {
            serviceRow
            lockTimerRow
            consentRow
            historyRow
            vaultKeyRow
            if let outcome = failure(.lockTimer, .consent, .history, .vaultKey) {
                failureRow(outcome)
            }
        }
    }

    /// What the header used to say, on the card it is about: the timer and
    /// the consent switch are jit's, and cannot change while it is down.
    @ViewBuilder private var serviceRow: some View {
        if !facts.serviceRunning {
            AppNoteRow(
                mark: .dot(Color(StatusMark.red)),
                name: "jit is not running",
                fact: "The lock timer and the consent switch need it to change."
            ) {
                Button("Start Service", action: actions.startService).buttonStyle(AppButton())
            }
        }
    }

    @ViewBuilder private var lockTimerRow: some View {
        if applying(.lockTimer) {
            AppNoteRow(mark: .busy, name: "Lock the vault after", fact: "Setting the timer, then jit restarts…") {
                EmptyView()
            }
        } else {
            AppRow(
                name: "Lock the vault after",
                fact: "Idle time before it locks; the next use asks Touch ID. Changing it restarts jit.",
                wraps: true
            ) {
                AppPopup(
                    options: Self.ttls.map { AppSegmentItem(value: $0.value, title: $0.label) },
                    selection: ttlBinding
                )
                .disabled(model.settingsApplying != nil || !facts.serviceRunning)
            }
        }
    }

    @ViewBuilder private var consentRow: some View {
        if applying(.consent) {
            AppNoteRow(
                mark: .busy,
                name: "Ask before a tool's first use",
                fact: "Waiting for Touch ID, then jit restarts…"
            ) {
                EmptyView()
            }
        } else {
            AppRow(
                name: "Ask before a tool's first use",
                fact: "You see which tool asked before it gets a secret. Changing it restarts jit.",
                wraps: true
            ) {
                AppSwitch(isOn: consentBinding)
                    .disabled(model.settingsApplying != nil || model.consentEnabled == nil)
            }
        }
    }

    @ViewBuilder private var historyRow: some View {
        if applying(.history) {
            AppNoteRow(
                mark: .busy,
                name: "Keep typed secrets out of zsh history",
                fact: "Changing the hook in your shell…",
                last: historyIsLast
            ) {
                EmptyView()
            }
        } else {
            AppRow(
                name: "Keep typed secrets out of zsh history",
                fact: "The command still runs; the history file never gets the secret.",
                wraps: true,
                last: historyIsLast
            ) {
                AppSwitch(isOn: guardBinding)
                    .disabled(model.settingsApplying != nil || model.guardInstalled == nil)
            }
        }
    }

    /// The history row is the card's last only with no Vault key row and
    /// no failure under it.
    private var historyIsLast: Bool {
        !showsVaultKeyRow && failure(.lockTimer, .consent, .history, .vaultKey) == nil
    }

    /// Drawn only where the move can work (`VaultKeyRow.state`). A failure
    /// of the move takes the row's place, as the card's failure row.
    private var showsVaultKeyRow: Bool {
        vaultKeyState != nil && failure(.vaultKey) == nil
    }

    /// Where the vault key is kept, and the one move from there: into the
    /// Secure Enclave, or back to the keychain from ···.
    @ViewBuilder private var vaultKeyRow: some View {
        let last = failure(.lockTimer, .consent, .history, .vaultKey) == nil
        if let state = vaultKeyState, showsVaultKeyRow {
            if applying(.vaultKey) {
                AppNoteRow(mark: .busy, name: Format.vaultKeyMoving, fact: Format.vaultKeyWaiting, last: last) {
                    EmptyView()
                }
            } else {
                vaultKeyStateRow(state, last: last)
            }
        }
    }

    @ViewBuilder private func vaultKeyStateRow(_ state: VaultKeyRow, last: Bool) -> some View {
        let detail = Format.vaultKeyDetail(state, now: model.vaultKeyPlace)
        switch state {
        case .keychain:
            AppRow(
                name: Format.vaultKeyName, detail: detail,
                fact: Format.vaultKeyFact(state, movable: model.canMoveVaultKeyIn), wraps: true, last: last
            ) {
                // Not on an empty vault: jit reports no recovery file for
                // one, so the sheet's Move Key could never open.
                if model.canMoveVaultKeyIn {
                    Button("Move to Secure Enclave…", action: actions.moveVaultKey)
                        .buttonStyle(AppButton())
                        .disabled(model.settingsApplying != nil)
                }
            }
        case .secureEnclave, .copyInKeychain:
            vaultKeyEnclaveRow(state, detail: detail, last: last)
        case .unchecked:
            // No colour, since nothing confirmed this Mac has the key, but
            // never a dead end: the check can run again, and the way back
            // stays where it always is.
            AppRow(name: Format.vaultKeyName, detail: detail, fact: Format.vaultKeyFact(state), wraps: true, last: last) {
                HStack(spacing: Design.Space.three) {
                    checkAgainButton
                    moveBackMenu
                }
            }
        case .checking:
            // No colour and no move until doctor says this Mac has the key.
            AppRow(name: Format.vaultKeyName, detail: detail, fact: Format.vaultKeyFact(state), wraps: true, last: last) {
                EmptyView()
            }
        case .lost, .restorePending:
            AppRow(
                dot: Color(StatusMark.red),
                name: Format.vaultKeyName, detail: detail, fact: Format.vaultKeyFact(state), wraps: true, last: last
            ) {
                Button("Restore from Recovery File…", action: actions.restoreVaultKey).buttonStyle(AppButton())
            }
        case .restoreUnchecked, .changeUnknown:
            vaultKeyBlockedRow(state, detail: detail, last: last)
        case .unfinished:
            // Red, as `jit status` shows it: every vault change is refused
            // until the move ends, and doctor counts it a problem.
            AppRow(
                dot: Color(StatusMark.red),
                name: Format.vaultKeyName, detail: detail, fact: Format.vaultKeyFact(state), wraps: true, last: last
            ) {
                Button(Format.vaultKeyRetryTitle(finishes: true), action: actions.retryVaultKey)
                    .buttonStyle(AppButton())
                    .disabled(model.settingsApplying != nil)
            }
        }
    }

    /// The key in the Secure Enclave: green, or red while a key is still
    /// in the keychain under its name. The vault opens, but that key is
    /// what the move was meant to end. Its fix is jit's, on Doctor's card,
    /// so the red row links there as the AI Agents rows link to another
    /// window ("Findings…", "Grants…"): a plain "Doctor…" beside the fact
    /// that says Doctor can remove it. Move Back stays in ··· either way.
    @ViewBuilder private func vaultKeyEnclaveRow(_ state: VaultKeyRow, detail: String, last: Bool) -> some View {
        let copyLeft = state == .copyInKeychain
        AppRow(
            dot: Color(copyLeft ? StatusMark.red : StatusMark.green),
            name: Format.vaultKeyName, detail: detail, fact: Format.vaultKeyFact(state), wraps: true, last: last
        ) {
            HStack(spacing: Design.Space.three) {
                if copyLeft {
                    Button(Format.vaultKeyOpenDoctor, action: actions.openDoctorForKeyCopy)
                        .buttonStyle(AppButton(kind: .plain))
                        .fixedSize()
                }
                moveBackMenu
            }
        }
    }

    /// The states where jit names no fix of its own, or none the row
    /// could press: a restore jit could not check, and a change of the key
    /// jit doesn't understand.
    @ViewBuilder private func vaultKeyBlockedRow(_ state: VaultKeyRow, detail: String, last: Bool) -> some View {
        switch state {
        case .restoreUnchecked:
            // Amber, a question: jit could not check, so it does not know
            // whether anything is left to restore. No Restore, since jit
            // names none; only what doctor's finding names, and Check Again.
            AppRow(
                dot: Color(StatusMark.amber),
                name: Format.vaultKeyName, detail: detail, fact: Format.vaultKeyFact(state), wraps: true, last: last
            ) {
                HStack(spacing: Design.Space.three) {
                    if let restore = model.vaultKeyRestore {
                        Button(restore.action.buttonTitle, action: actions.restoreVaultKey)
                            .buttonStyle(AppButton())
                            .fixedSize()
                            .disabled(model.settingsApplying != nil)
                    }
                    checkAgainButton
                }
            }
        case .changeUnknown:
            // Red: every vault change is refused, a move too, and nothing
            // this app can press ends it. jit's words say what does.
            AppRow(
                dot: Color(StatusMark.red),
                name: Format.vaultKeyName, detail: detail, fact: Format.vaultKeyFact(state), wraps: true, last: last
            ) {
                checkAgainButton
            }
        default:
            EmptyView()
        }
    }

    private var checkAgainButton: some View {
        Button(Format.vaultKeyCheckAgain, action: actions.checkVaultKeyAgain)
            .buttonStyle(AppButton())
            .fixedSize()
            .disabled(model.settingsApplying != nil)
    }

    /// ···, holding Move Back to Keychain…
    private var moveBackMenu: some View {
        Menu {
            Button("Move Back to Keychain…", action: actions.moveVaultKeyBack)
        } label: {
            Text("···")
        }
        .menuStyle(.button)
        .buttonStyle(AppButton())
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.settingsApplying != nil)
    }

    // MARK: - Bindings

    private var ttlBinding: Binding<String> {
        Binding(
            get: { Self.ttls.first { $0.value == Format.duration(seconds: model.ttlSeconds) }?.value ?? "5m" },
            set: { value in
                actions.setTTL(value, Self.ttls.first { $0.value == value }?.label ?? value)
            }
        )
    }

    private var consentBinding: Binding<Bool> {
        Binding(get: { model.consentEnabled ?? true }, set: actions.setConsent)
    }

    private var guardBinding: Binding<Bool> {
        Binding(get: { model.guardInstalled ?? false }, set: actions.setGuard)
    }
}
