// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Settings, built from the window system (`docs/design/mockups/
/// Settings-v2.html` and the design system's Windows page): banner,
/// toolbar, body at one inset, holding a card or two per segment, holding
/// one row per setting. No header: the title bar names the window, and
/// what the header used to say is on the row it is about.
struct SettingsView: View {
    @ObservedObject var model: MenuModel
    let actions: SettingsActions

    /// The segment the toolbar is on. A card that needs the reader can sit
    /// behind another pill, which is why the pills carry dots.
    @State var segment: SettingsSegment = .general

    var body: some View {
        VStack(spacing: 0) {
            if let outcome = model.settingsOutcome, outcome.ok {
                WindowBanner(tint: Color(StatusMark.green), text: outcome.title)
            }
            AppSegmented(items: pills, selection: $segment).windowRegion()
            ScrollView {
                VStack(alignment: .leading, spacing: Win.s5) {
                    ForEach(segment.groups) { card($0) }
                }
                .padding(Win.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(
            minWidth: Win.widthSmall, maxWidth: .infinity,
            minHeight: Win.minimum(Win.heightSmall), maxHeight: .infinity,
            alignment: .top
        )
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .sheet(isPresented: $model.vaultKeySheet) {
            VaultKeySheet(model: model, actions: actions)
        }
        // The move is a Protection setting wherever it was asked for
        // (Doctor's offer opens it here), and its spinner and outcome land
        // on that card's row.
        .onChange(of: model.vaultKeySheet) { _, open in
            if open {
                segment = .protection
            }
        }
    }

    // MARK: - Regions

    private var pills: [AppSegmentItem<SettingsSegment>] {
        facts.segments.map {
            AppSegmentItem(
                value: $0,
                title: $0.title,
                dot: pillDot(facts.worst(in: $0))
            )
        }
    }

    private func pillDot(_ state: SettingsState?) -> Color? {
        switch state {
        case .broken: Color(StatusMark.red)
        case .needsYou: Color(StatusMark.amber)
        default: nil
        }
    }

    @ViewBuilder private func card(_ group: SettingsGroup) -> some View {
        switch group {
        case .general: generalCard
        case .protection: protectionCard
        case .notifications: notificationsCard
        case .scan: scanCard
        case .excludes: excludesCard
        case .reset: resetCard
        }
    }

    // MARK: - What the dots depend on

    var facts: SettingsFacts {
        SettingsFacts(
            serviceRunning: model.consentEnabled != nil,
            notificationsWanted: model.notifyDecoys || model.notifySessions || model.notifyScans || model.notifyJobs,
            notificationsBlocked: model.notificationPermission == .denied || model.notificationPermission == .notAsked,
            scanScheduled: model.scanSchedule != .off,
            fullDiskAccess: model.fullDiskAccess,
            updateAvailable: model.updateAvailable != nil,
            jitOnPath: jitOnPath,
            vaultKey: vaultKeyState
        )
    }

    private var jitOnPath: Bool {
        switch model.cliTool {
        case .linked, nil: true
        case .other, .missing: false
        }
    }

    /// The failure belonging to one of these rows, if the last change
    /// failed there. A refusal is reported under the control that asked,
    /// never under the window.
    func failure(_ rows: SettingsOutcome.Row...) -> SettingsOutcome? {
        guard let outcome = model.settingsOutcome, !outcome.ok, rows.contains(outcome.row) else {
            return nil
        }
        return outcome
    }

    /// Where the vault key is kept, or nil where the row is not drawn.
    var vaultKeyState: VaultKeyRow? {
        model.vaultKeyRow
    }

    /// The row a change is being applied to, so the spinner sits on it
    /// rather than under the whole window.
    func applying(_ row: SettingsOutcome.Row) -> Bool {
        model.settingsApplying == row
    }

    /// A failure's own row: the cross, the sentence that translates it,
    /// jit's words under that, and the one button that unblocks it.
    func failureRow(_ outcome: SettingsOutcome, last: Bool = true) -> some View {
        AppNoteRow(
            mark: .failed,
            name: outcome.title,
            fact: outcome.detail,
            verbatim: outcome.verbatim,
            last: last
        ) {
            if outcome.offersStart {
                Button("Start Service", action: actions.startService).buttonStyle(AppButton())
            }
            if outcome.offersCheck {
                Button(Format.vaultKeyCheckAgain, action: actions.checkVaultKeyAgain)
                    .buttonStyle(AppButton())
            }
            if outcome.offersRetry, let retry = model.vaultKeyRetry {
                Button(Format.vaultKeyRetryTitle(finishes: retry.finishes), action: actions.retryVaultKey)
                    .buttonStyle(AppButton())
            }
        }
    }
}
