// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Scan segment: the one group that reads your disk, and the folders
/// it is told to leave alone.
extension SettingsView {
    var scanCard: some View {
        AppCard(
            eyebrow: SettingsGroup.scan.title,
            eyebrowTint: eyebrowTint(.scan),
            title: "Looking for secrets this Mac still keeps",
            note: "jit reads your home folder, shell configs, credential files and agent caches. Nothing leaves this Mac."
        ) {
            Button("Exclude a Folder…", action: actions.addExclude).buttonStyle(AppButton())
        } rows: {
            AppCardRows {
                accessRow
                scheduleRow
                redactRow
                excludeRows
            }
        }
    }

    /// Full Disk Access is a scheduled scan's problem: a scan someone
    /// clicked is standing in front of the prompts.
    @ViewBuilder private var accessRow: some View {
        if facts.state(of: .scan) == .needsYou {
            AppNoteRow(
                mark: .dot(Color(StatusMark.amber)),
                name: "Waiting for Full Disk Access",
                fact: "A scheduled scan skips Desktop, Documents and Downloads until macOS allows it."
            ) {
                Button("Open System Settings…", action: actions.grantFullDiskAccess).buttonStyle(AppButton())
            }
        }
    }

    /// The one automatic Protect: after a scheduled scan, the tokens it
    /// found by format in agent caches become markers. Off by default. The
    /// row carries every guard, since a switch never asks.
    private var redactRow: some View {
        AppRow(
            name: "After a scheduled scan, redact tokens in agent caches",
            fact: "Only AI agent caches, never your files. Each token becomes a marker that says what it was; "
                + "there is no backup and no undo. No Touch ID: it runs after every scheduled scan and tells you what it changed.",
            wraps: true,
            last: model.scanExcludes.isEmpty
        ) {
            AppSwitch(isOn: Binding(get: { model.redactAfterScan }, set: actions.setRedactAfterScan))
        }
    }

    private var scheduleRow: some View {
        AppRow(
            name: "Scan the whole Mac",
            fact: scheduleFact,
            wraps: true
        ) {
            AppPopup(
                options: ScanSchedule.allCases.map { AppSegmentItem(value: $0, title: $0.label) },
                selection: scheduleBinding
            )
        }
    }

    private var scheduleFact: String {
        if model.scanSchedule == .off {
            return "Every scan is a click. Nothing runs on its own."
        }
        return model.fullDiskAccess
            ? "Runs quietly, and again after a Protect."
            : "Runs quietly, and again after a Protect — within what macOS allows."
    }

    /// A list says what is true, not that it is empty.
    @ViewBuilder private var excludeRows: some View {
        if model.scanExcludes.isEmpty {
            AppRow(
                name: "Every folder in your home is scanned",
                fact: "Nothing is excluded yet.",
                wraps: true,
                last: true
            ) {
                EmptyView()
            }
        } else {
            ForEach(Array(model.scanExcludes.enumerated()), id: \.element) { index, path in
                AppRow(
                    name: Format.fileName(path),
                    detail: Format.parentFolder(path),
                    fact: "Skipped by every scan",
                    last: index == model.scanExcludes.count - 1
                ) {
                    Button("Remove") { actions.removeExclude(path) }.buttonStyle(AppButton())
                }
            }
        }
    }

    private var scheduleBinding: Binding<ScanSchedule> {
        Binding(get: { model.scanSchedule }, set: actions.setScanSchedule)
    }
}
