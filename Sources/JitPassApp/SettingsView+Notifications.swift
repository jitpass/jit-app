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
                fact: "Something read a protected file without a run or consent, and got fake values.",
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
                fact: "A secret the last scan did not have, or tokens it redacted. Findings has the list.",
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
                    name: "macOS has notifications off for JitPass",
                    fact: "The switches stay set. Nothing arrives until macOS allows it."
                ) {
                    Button("Open System Settings…", action: actions.openNotificationSettings).buttonStyle(AppButton())
                }
            } else {
                AppNoteRow(
                    mark: .dot(Color(StatusMark.amber)),
                    name: "macOS has not been asked yet",
                    fact: "The first time one of these arrives, macOS asks. You can answer it now instead."
                ) {
                    Button("Allow Notifications…", action: actions.allowNotifications).buttonStyle(AppButton())
                }
            }
        }
    }
}
