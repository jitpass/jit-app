// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Settings › General, the bottom: which JitPass this is and whether a
/// newer one exists, and whether a terminal's `jit` is this app's. Both
/// exist for a copy downloaded from the website; a Homebrew install has
/// `brew upgrade` for the first and the cask's link for the second, and
/// the rows say so rather than compete.
struct SettingsUpdatesSection: View {
    @ObservedObject var model: MenuModel
    let actions: SettingsActions

    private var version: String {
        UpdateCheck.current.map { "\($0)" } ?? "development build"
    }

    var body: some View {
        Section("Updates") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("JitPass \(version)")
                    Text(updateDetail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.updateChecking {
                    ProgressView().controlSize(.small)
                } else if model.updateAvailable != nil {
                    Button("Update…", action: actions.installUpdate)
                } else {
                    Button("Check Now", action: actions.checkForUpdates)
                }
            }
            Toggle("Check for updates daily", isOn: checkBinding)
                .help("One request a day to github.com asking which release is latest. Nothing about this Mac is sent. "
                    + "The only network request the app makes.")
        }
        Section("Command line tool") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cliTitle)
                    if let detail = cliDetail {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                if showInstall {
                    Button("Install…", action: actions.installCommandLineTool)
                }
            }
            .help("A symlink named jit in your PATH pointing at the copy inside this app, the same link the "
                + "jitpass cask makes. Homebrew's bin needs no password; /usr/local/bin asks for one.")
        }
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

    private var cliTitle: String {
        switch model.cliTool {
        case .linked: "jit is on your PATH"
        case .other: "A different jit is on your PATH"
        case .missing: "jit is not on your PATH"
        case nil: "No jit inside this build"
        }
    }

    private var cliDetail: String? {
        switch model.cliTool {
        case let .linked(path): path
        case let .other(path): "\(path) is not the copy inside this app."
        case .missing: "Terminals cannot run jit until it is linked."
        case nil: nil
        }
    }

    private var showInstall: Bool {
        switch model.cliTool {
        case .linked, nil: false
        case .other, .missing: true
        }
    }

    private var checkBinding: Binding<Bool> {
        Binding(get: { model.checkForUpdates }, set: actions.setCheckForUpdates)
    }
}
