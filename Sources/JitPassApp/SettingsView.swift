// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Settings: the app's own two preferences, and the two service settings
/// the CLI exposes, applied through the CLI so the terminal and the app can
/// never disagree about what a setting means.
struct SettingsView: View {
    @ObservedObject var model: MenuModel
    let actions: SettingsActions

    private static let ttls: [(label: String, value: String)] = [
        ("5 minutes", "5m"), ("15 minutes", "15m"), ("30 minutes", "30m"), ("1 hour", "1h"),
        ("2 hours", "2h"), ("4 hours", "4h"), ("8 hours", "8h")
    ]

    private static let restartNote = "Changing either restarts the service; the next vault use prompts Touch ID once. "
        + "Turning consent off asks for Touch ID now."

    var body: some View {
        Form {
            Section("JitPass") {
                Picker("Open commands in", selection: terminalBinding) {
                    ForEach(Terminal.choices, id: \.self) { Text($0.isEmpty ? "the terminal you are using" : $0).tag($0) }
                }
                Picker("Open files with", selection: editorBinding) {
                    Text("the system default").tag("")
                    ForEach(model.editors) { Text($0.name).tag($0.bundleID) }
                }
                Toggle("Launch at login", isOn: launchBinding)
            }
            Section("Scan") {
                if model.scanExcludes.isEmpty {
                    Text("No folders are excluded.").foregroundStyle(.secondary)
                }
                ForEach(model.scanExcludes, id: \.self) { path in
                    HStack {
                        Text(Format.home(path)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { actions.removeExclude(path) }.buttonStyle(.link)
                    }
                }
                Button("Exclude a Folder…", action: actions.addExclude)
                Text("Excluded folders are skipped by every scan, and the report says so.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Service") {
                Picker("Lock the session after", selection: ttlBinding) {
                    ForEach(Self.ttls, id: \.value) { Text($0.label).tag($0.value) }
                }
                .disabled(model.settingsBusy)
                Toggle("Ask before each tool's first credential use", isOn: consentBinding)
                    .disabled(model.settingsBusy || model.consentEnabled == nil)
                Text(Self.restartNote)
                    .font(.subheadline).foregroundStyle(.secondary)
                if model.settingsBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Applying…").foregroundStyle(.secondary)
                    }
                }
                if let message = model.settingsMessage {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 460)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
    }

    private var terminalBinding: Binding<String> {
        Binding(get: { model.terminalApp }, set: actions.setTerminal)
    }

    private var editorBinding: Binding<String> {
        Binding(get: { model.editorApp }, set: actions.setEditor)
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { model.launchAtLogin }, set: actions.setLaunchAtLogin)
    }

    private var ttlBinding: Binding<String> {
        Binding(
            get: { Self.ttls.first { $0.value == Format.duration(seconds: model.ttlSeconds) }?.value ?? "5m" },
            set: actions.setTTL
        )
    }

    private var consentBinding: Binding<Bool> {
        Binding(get: { model.consentEnabled ?? true }, set: actions.setConsent)
    }
}

struct SettingsActions {
    var addExclude: () -> Void = {}
    var removeExclude: (String) -> Void = { _ in }
    var setTerminal: (String) -> Void = { _ in }
    var setEditor: (String) -> Void = { _ in }
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var setTTL: (String) -> Void = { _ in }
    var setConsent: (Bool) -> Void = { _ in }
}
