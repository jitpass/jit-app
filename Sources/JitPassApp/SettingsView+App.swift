// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The App segment: how JitPass behaves on this Mac, which build this is
/// and the jit beside it, and how the app leaves.
extension SettingsView {
    var thisMacCard: some View {
        AppCard(
            eyebrow: SettingsGroup.thisMac.title,
            eyebrowTint: eyebrowTint(.thisMac),
            title: "How JitPass behaves here"
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                AppRow(
                    name: "Launch at login",
                    fact: "The menu bar item comes back after a restart. jit's service runs either way.",
                    wraps: true
                ) {
                    AppSwitch(isOn: launchBinding)
                }
                AppRow(
                    name: "Open commands in",
                    fact: "Where a command JitPass hands over is run.",
                    wraps: true
                ) {
                    AppPopup(options: terminalOptions, selection: terminalBinding)
                }
                AppRow(
                    name: "Open files with",
                    fact: "Opening a file from Doctor or Scan uses this app.",
                    wraps: true,
                    last: failure(.launchAtLogin) == nil
                ) {
                    AppPopup(options: editorOptions, selection: editorBinding)
                }
                if let outcome = failure(.launchAtLogin) {
                    failureRow(outcome)
                }
            }
        }
    }

    private var terminalOptions: [AppSegmentItem<String>] {
        Terminal.choices.map {
            AppSegmentItem(value: $0, title: $0.isEmpty ? "the terminal you are using" : $0)
        }
    }

    private var editorOptions: [AppSegmentItem<String>] {
        [AppSegmentItem(value: "", title: "the system default")]
            + model.editors.map { AppSegmentItem(value: $0.bundleID, title: $0.name) }
    }

    // MARK: - Updates

    var updatesCard: some View {
        AppCard(
            eyebrow: SettingsGroup.updates.title,
            eyebrowTint: eyebrowTint(.updates),
            title: "This build, and the jit beside it"
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                versionRow
                AppRow(
                    name: "Check for updates daily",
                    fact: "One request a day to github.com asking which release is latest. Nothing about this Mac is sent.",
                    wraps: true
                ) {
                    AppSwitch(isOn: checkBinding)
                }
                commandLineRow
                if let outcome = failure(.commandLineTool) {
                    failureRow(outcome)
                }
            }
        }
    }

    private var versionRow: some View {
        AppRow(name: "JitPass \(version)", fact: updateDetail, wraps: true) {
            if model.updateChecking {
                ProgressView().controlSize(.small)
            } else if model.updateAvailable != nil {
                Button("Update…", action: actions.installUpdate).buttonStyle(AppButton(kind: .primary))
            } else {
                Button("Check Now", action: actions.checkForUpdates).buttonStyle(AppButton())
            }
        }
    }

    private var version: String {
        UpdateCheck.current.map { "\($0)" } ?? "development build"
    }

    private var updateDetail: String {
        if let message = model.updateMessage {
            return message
        }
        if let update = model.updateAvailable {
            return "\(update) is available."
        }
        if let checked = model.updateChecked {
            return "Last checked \(Format.ago(checked))."
        }
        return model.checkForUpdates ? "Not checked yet." : "Checks are off."
    }

    /// The jit a terminal runs, and whether it is this app's copy.
    @ViewBuilder private var commandLineRow: some View {
        let last = failure(.commandLineTool) == nil
        switch model.cliTool {
        case let .linked(path):
            AppRow(name: "jit is on your PATH", detail: path, last: last) { EmptyView() }
        case let .other(path):
            AppNoteRow(
                mark: .dot(Color(StatusMark.amber)),
                name: "A different jit is on your PATH",
                fact: "\(Format.home(path)) is not the copy inside this app.",
                last: last
            ) {
                Button("Install…", action: actions.installCommandLineTool).buttonStyle(AppButton())
            }
        case .missing:
            AppNoteRow(
                mark: .dot(Color(StatusMark.amber)),
                name: "jit is not on your PATH",
                fact: "Terminals cannot run jit until it is linked.",
                last: last
            ) {
                Button("Install…", action: actions.installCommandLineTool).buttonStyle(AppButton())
            }
        case nil:
            AppRow(name: "No jit inside this build", last: last) { EmptyView() }
        }
    }

    // MARK: - Remove

    var removeCard: some View {
        AppCard(
            eyebrow: SettingsGroup.remove.title,
            eyebrowTint: eyebrowTint(.remove),
            title: "Put this Mac back the way it was",
            note: "Every file returns to what it held before JitPass, and the app leaves. You see the full list first."
        ) {
            Button("Remove JitPass…", action: actions.removeJitPass).buttonStyle(AppButton(kind: .secondary))
        } rows: {
            EmptyView()
        }
    }

    // MARK: - Bindings

    private var launchBinding: Binding<Bool> {
        Binding(get: { model.launchAtLogin }, set: actions.setLaunchAtLogin)
    }

    private var terminalBinding: Binding<String> {
        Binding(get: { model.terminalApp }, set: actions.setTerminal)
    }

    private var editorBinding: Binding<String> {
        Binding(get: { model.editorApp }, set: actions.setEditor)
    }

    private var checkBinding: Binding<Bool> {
        Binding(get: { model.checkForUpdates }, set: actions.setCheckForUpdates)
    }
}
