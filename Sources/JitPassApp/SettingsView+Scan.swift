// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Scan segment: the one group that reads your disk, and, in a card of
/// its own, the folders it is told to leave alone.
extension SettingsView {
    var scanCard: some View {
        AppPlainCard {
            accessRow
            scheduleRow
            redactRow
        }
    }

    /// The folders every scan leaves alone: a list, so it is a card with a
    /// title of its own and the verb that adds to it.
    var excludesCard: some View {
        AppPlainCard(title: SettingsGroup.excludes.title) {
            Button("Add Folder…", action: actions.addExclude).buttonStyle(AppButton())
        } rows: {
            excludeRows
        }
    }

    /// Full Disk Access is a scheduled scan's problem: a scan someone
    /// clicked is standing in front of the prompts.
    @ViewBuilder private var accessRow: some View {
        if facts.state(of: .scan) == .needsYou {
            AppNoteRow(
                mark: .dot(Color(StatusMark.amber)),
                name: "Waiting for Full Disk Access",
                fact: "Until then a scheduled scan skips Desktop, Documents and Downloads."
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
            name: "Redact agent caches after a scheduled scan",
            fact: "Only AI agent caches, never your files. Each token becomes a marker that says what it was. "
                + "No backup, no undo, no Touch ID; you are told what changed.",
            wraps: true,
            last: true
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
            return "Every scan is a click. Nothing leaves this Mac."
        }
        return model.fullDiskAccess
            ? "Runs quietly, and again after a Protect. Nothing leaves this Mac."
            : "Runs quietly, within what macOS allows. Nothing leaves this Mac."
    }

    /// A list says what is true, not that it is empty.
    @ViewBuilder private var excludeRows: some View {
        if model.scanExcludes.isEmpty {
            AppRow(
                name: "None yet",
                fact: "Every folder in your home is scanned.",
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
