// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Settings, built from the window system (`docs/design/mockups/
/// Settings-redesign.html` and the design system's Windows page): banner,
/// header, toolbar, body at one inset, holding one card per group, holding
/// one row per setting. The three macOS tabs are three segments, and every
/// sentence that used to wait for a hover is on screen.
struct SettingsView: View {
    @ObservedObject var model: MenuModel
    let actions: SettingsActions

    /// The segment the toolbar is on. A card that needs the reader can sit
    /// behind another pill, which is why the pills carry dots.
    @State var segment: SettingsSegment = .protection

    var body: some View {
        VStack(spacing: 0) {
            if let outcome = model.settingsOutcome, outcome.ok {
                WindowBanner(tint: Color(StatusMark.green), text: outcome.title)
            }
            header
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
    }

    // MARK: - Regions

    /// The name, and the one thing that changes how the rest is read:
    /// there is no Save button, and two of these settings are jit's.
    private var header: some View {
        HStack(spacing: Win.s5) {
            WindowMark(tint: Color(facts.serviceRunning ? StatusMark.green : StatusMark.amber))
            VStack(alignment: .leading, spacing: Win.s1) {
                Text("Settings").font(Win.head)
                Text(subline).font(Win.sub).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Win.s5)
        }
        .windowRegion()
    }

    private var subline: String {
        facts.serviceRunning
            ? "Every change applies as you make it. The two jit owns restart the service."
            : "jit is not running, so the two settings it owns cannot be changed here yet."
    }

    private var pills: [AppSegmentItem<SettingsSegment>] {
        facts.segments.map {
            AppSegmentItem(
                value: $0,
                title: $0.title,
                dot: facts.needsYou(in: $0) ? Color(StatusMark.amber) : nil
            )
        }
    }

    @ViewBuilder private func card(_ group: SettingsGroup) -> some View {
        switch group {
        case .protection: protectionCard
        case .notifications: notificationsCard
        case .vault: vaultCard
        case .scan: scanCard
        case .thisMac: thisMacCard
        case .updates: updatesCard
        case .remove: removeCard
        }
    }

    // MARK: - What the dots depend on

    var facts: SettingsFacts {
        SettingsFacts(
            serviceRunning: model.consentEnabled != nil,
            notificationsWanted: model.notifyDecoys || model.notifyChanges,
            notificationsBlocked: model.notificationPermission == .denied || model.notificationPermission == .notAsked,
            scanScheduled: model.scanSchedule != .off,
            fullDiskAccess: model.fullDiskAccess,
            updateAvailable: model.updateAvailable != nil,
            jitOnPath: jitOnPath
        )
    }

    private var jitOnPath: Bool {
        switch model.cliTool {
        case .linked, nil: true
        case .other, .missing: false
        }
    }

    /// A card's eyebrow: the group's word, and the dot that goes with it.
    func eyebrowTint(_ group: SettingsGroup) -> Color {
        switch facts.state(of: group) {
        case .needsYou: Color(StatusMark.amber)
        case .healthy: Color(StatusMark.green)
        case .none: .secondary
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
        }
    }
}
