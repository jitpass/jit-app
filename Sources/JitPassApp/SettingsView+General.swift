// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The General segment: how JitPass behaves on this Mac, which build this
/// is, and the jit beside it. One card, so no eyebrow.
extension SettingsView {
    var generalCard: some View {
        AppPlainCard {
            AppRow(
                name: "Launch at login",
                fact: "The menu bar item comes back after a restart. jit runs either way.",
                wraps: true
            ) {
                AppSwitch(isOn: launchBinding)
            }
            AppRow(name: "Open commands in") {
                AppPopup(options: terminalOptions, selection: terminalBinding)
            }
            AppRow(name: "Open files with") {
                AppPopup(options: editorOptions, selection: editorBinding)
            }
            if let outcome = failure(.launchAtLogin) {
                failureRow(outcome, last: false)
            }
            versionRow
            AppRow(
                name: "Check for updates daily",
                fact: "One request a day to github.com. Nothing about this Mac is sent.",
                wraps: true,
                last: !commandLineNeedsYou && failure(.commandLineTool) == nil
            ) {
                AppSwitch(isOn: checkBinding)
            }
            commandLineRow
            if let outcome = failure(.commandLineTool) {
                failureRow(outcome)
            }
        }
    }

    private var terminalOptions: [AppSegmentItem<String>] {
        Terminal.choices.map {
            AppSegmentItem(value: $0, title: $0.isEmpty ? "The terminal you're using" : $0)
        }
    }

    private var editorOptions: [AppSegmentItem<String>] {
        [AppSegmentItem(value: "", title: "System default")]
            + model.editors.map { AppSegmentItem(value: $0.bundleID, title: $0.name) }
    }

    // MARK: - Updates

    @ViewBuilder private var versionRow: some View {
        if model.updateAvailable != nil, !model.updateChecking {
            AppNoteRow(mark: .dot(Color(StatusMark.amber)), name: "JitPass \(version)", fact: updateDetail) {
                Button("Update…", action: actions.installUpdate).buttonStyle(AppButton(kind: .primary))
            }
        } else {
            AppRow(name: "JitPass \(version)", fact: updateDetail) {
                if model.updateChecking {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Check Now", action: actions.checkForUpdates).buttonStyle(AppButton())
                }
            }
        }
    }

    private var version: String {
        UpdateCheck.current.map { "\($0)" } ?? "development build"
    }

    /// The build's state, then where jit stands while that needs no row of
    /// its own. A check's own sentence, when there is one, stands alone.
    private var updateDetail: String {
        if let message = model.updateMessage {
            return message
        }
        let state: String = if let update = model.updateAvailable {
            "\(update) is available"
        } else if let checked = model.updateChecked {
            "Up to date · checked \(Format.ago(checked))"
        } else {
            model.checkForUpdates ? "Not checked yet" : "Checks are off"
        }
        return commandLineNeedsYou ? state : state + " · jit is on your PATH"
    }

    // MARK: - The jit on PATH

    /// Only a jit that is not this app's copy gets a row: a healthy link
    /// is a fact on the version line, not a row with nothing to do.
    private var commandLineNeedsYou: Bool {
        switch model.cliTool {
        case .other, .missing, nil: true
        case .linked: false
        }
    }

    @ViewBuilder private var commandLineRow: some View {
        let last = failure(.commandLineTool) == nil
        switch model.cliTool {
        case .linked:
            EmptyView()
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
