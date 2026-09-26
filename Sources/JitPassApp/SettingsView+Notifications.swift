// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Notifications segment: one switch per event JitPass can tell you
/// about, and what macOS allows, said only where a switch is on.
extension SettingsView {
    var notificationsCard: some View {
        AppPlainCard {
            permissionRow
            AppRow(
                name: "A decoy was served",
                fact: "A read with no run or consent behind it got fake values.",
                wraps: true
            ) {
                AppSwitch(isOn: Binding(get: { model.notifyDecoys }, set: actions.setNotifyDecoys))
            }
            AppRow(
                name: "A session expires",
                fact: "The next aws call fails until you renew.",
                wraps: true
            ) {
                AppSwitch(isOn: Binding(get: { model.notifySessions }, set: actions.setNotifySessions))
            }
            AppRow(
                name: "A scheduled scan finds something new",
                fact: "A secret the last scan didn't have, or tokens it redacted.",
                wraps: true
            ) {
                AppSwitch(isOn: Binding(get: { model.notifyScans }, set: actions.setNotifyScans))
            }
            AppRow(
                name: "An AI job stops or is proposed",
                fact: "A changed file stopped a job, or an agent asks to add one.",
                wraps: true,
                last: true
            ) {
                AppSwitch(isOn: Binding(get: { model.notifyJobs }, set: actions.setNotifyJobs))
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
                    name: "Turned off in macOS",
                    fact: "The switches stay set; nothing arrives until you allow it."
                ) {
                    Button("Open System Settings…", action: actions.openNotificationSettings).buttonStyle(AppButton())
                }
            } else {
                AppNoteRow(
                    mark: .dot(Color(StatusMark.amber)),
                    name: "macOS has not asked yet",
                    fact: "It asks the first time one arrives; you can answer now."
                ) {
                    Button("Allow Notifications…", action: actions.allowNotifications).buttonStyle(AppButton())
                }
            }
        }
    }
}
