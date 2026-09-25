// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Protection segment: what jit hands out and when it asks, what
/// JitPass tells you about, and emptying the vault.
extension SettingsView {
    static let ttls: [(label: String, value: String)] = [
        ("5 minutes", "5m"), ("15 minutes", "15m"), ("30 minutes", "30m"), ("1 hour", "1h"),
        ("2 hours", "2h"), ("4 hours", "4h"), ("8 hours", "8h")
    ]

    var protectionCard: some View {
        AppCard(
            eyebrow: SettingsGroup.protection.title,
            eyebrowTint: eyebrowTint(.protection),
            title: "What jit hands out, and when it asks",
            note: "Changing the timer or the consent switch restarts the service. Open shells keep what they already loaded."
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                lockTimerRow
                consentRow
                historyRow
                vaultKeyRow
                if let outcome = failure(.lockTimer, .consent, .history, .vaultKey) {
                    failureRow(outcome)
                }
            }
        }
    }

    @ViewBuilder private var lockTimerRow: some View {
        if applying(.lockTimer) {
            AppNoteRow(mark: .busy, name: "Lock the session after", fact: "Setting the timer, then jit restarts…") {
                EmptyView()
            }
        } else {
            AppRow(
                name: "Lock the session after",
                fact: "Idle time before the vault locks. The next use asks Touch ID once.",
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
                name: "Ask before each tool's first credential use",
                fact: "Waiting for Touch ID, then jit restarts…"
            ) {
                EmptyView()
            }
        } else {
            AppRow(
                name: "Ask before each tool's first credential use",
                fact: "aws, git, docker — you see what asked before it gets a value.",
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
                name: "Keep typed credentials out of zsh history",
                fact: "Changing the hook in your shell…",
                last: historyIsLast
            ) {
                EmptyView()
            }
        } else {
            AppRow(
                name: "Keep typed credentials out of zsh history",
                fact: "A command carrying one still runs; the history file never gets it.",
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
        case .secureEnclave:
            AppRow(
                dot: Color(StatusMark.green),
                name: Format.vaultKeyName, detail: detail, fact: Format.vaultKeyFact(state), wraps: true, last: last
            ) {
                moveBackMenu
            }
        case .unchecked:
            // No colour, since nothing confirmed this Mac has the key, but
            // never a dead end: the check can run again, and the way back
            // stays where it always is.
            AppRow(name: Format.vaultKeyName, detail: detail, fact: Format.vaultKeyFact(state), wraps: true, last: last) {
                HStack(spacing: Design.Space.three) {
                    Button(Format.vaultKeyCheckAgain, action: actions.checkVaultKeyAgain)
                        .buttonStyle(AppButton())
                        .disabled(model.settingsApplying != nil)
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
        case .unfinished:
            AppRow(
                dot: Color(StatusMark.amber),
                name: Format.vaultKeyName, detail: detail, fact: Format.vaultKeyFact(state), wraps: true, last: last
            ) {
                Button(Format.vaultKeyRetryTitle(finishes: true), action: actions.retryVaultKey)
                    .buttonStyle(AppButton())
                    .disabled(model.settingsApplying != nil)
            }
        }
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

    // MARK: - Notifications

    var notificationsCard: some View {
        AppCard(
            eyebrow: SettingsGroup.notifications.title,
            eyebrowTint: eyebrowTint(.notifications),
            title: "What JitPass tells you about"
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                permissionRow
                AppRow(
                    name: "A decoy was served",
                    fact: "Something read a protected file with no run or consent behind it, and got fake values.",
                    wraps: true
                ) {
                    AppSwitch(isOn: notifyDecoysBinding)
                }
                AppRow(
                    name: "A session expires, or a scheduled scan finds something new",
                    fact: "The next aws call fails until you renew; or a scan found a secret the last one did not, and Findings has it.",
                    wraps: true
                ) {
                    AppSwitch(isOn: notifyChangesBinding)
                }
                AppRow(
                    name: "An AI job stops, or an AI tool proposes one",
                    fact: "A changed file stopped a job, or an agent asks to add one. Either waits for you in AI Jobs.",
                    wraps: true,
                    last: true
                ) {
                    AppSwitch(isOn: notifyJobsBinding)
                }
            }
        }
    }

    /// Said only where a switch is on: a permission nobody asked for is
    /// not a problem the reader has to solve.
    @ViewBuilder private var permissionRow: some View {
        if facts.state(of: .notifications) == .needsYou {
            if model.notificationPermission == .denied {
                AppNoteRow(
                    mark: .dot(Color(StatusMark.amber)),
                    name: "macOS has notifications off for JitPass",
                    fact: "The switches below stay set. Nothing is delivered until macOS allows it."
                ) {
                    Button("Open System Settings…", action: actions.openNotificationSettings).buttonStyle(AppButton())
                }
            } else {
                AppNoteRow(
                    mark: .dot(Color(StatusMark.amber)),
                    name: "macOS has not been asked yet",
                    fact: "The first time one of these is delivered, macOS asks. You can answer it now instead."
                ) {
                    Button("Allow Notifications…", action: actions.allowNotifications).buttonStyle(AppButton())
                }
            }
        }
    }

    // MARK: - Vault

    var vaultCard: some View {
        AppCard(
            eyebrow: SettingsGroup.vault.title,
            eyebrowTint: eyebrowTint(.vault),
            title: "Emptying the vault",
            note: "Both hand the last word to jit, which asks again in your terminal."
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                AppRow(
                    name: "Delete every secret, keep the key",
                    fact: "Every secret and every backup, gone for good. The vault stays usable.",
                    wraps: true
                ) {
                    Button("Clean in Terminal…", action: actions.vaultClean).buttonStyle(AppButton())
                }
                AppRow(
                    name: "Destroy the vault and its key",
                    fact: "The vault directory and its key. Nothing comes back.",
                    wraps: true,
                    last: true
                ) {
                    Button("Delete in Terminal…", action: actions.vaultDelete)
                        .buttonStyle(AppButton(kind: .destructive))
                }
            }
        }
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

    private var notifyDecoysBinding: Binding<Bool> {
        Binding(get: { model.notifyDecoys }, set: actions.setNotifyDecoys)
    }

    private var notifyChangesBinding: Binding<Bool> {
        Binding(get: { model.notifyChanges }, set: actions.setNotifyChanges)
    }

    private var notifyJobsBinding: Binding<Bool> {
        Binding(get: { model.notifyJobs }, set: actions.setNotifyJobs)
    }
}
