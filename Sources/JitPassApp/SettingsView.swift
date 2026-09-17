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

    var body: some View {
        TabView {
            general.tabItem { Text("General") }
            protection.tabItem { Text("Protection") }
            scan.tabItem { Text("Scan") }
        }
        .padding(.top, 8)
        .frame(width: 480, height: 420)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
    }

    // MARK: - General

    private var general: some View {
        Form {
            Picker("Open commands in", selection: terminalBinding) {
                ForEach(Terminal.choices, id: \.self) { Text($0.isEmpty ? "the terminal you are using" : $0).tag($0) }
            }
            Picker("Open files with", selection: editorBinding) {
                Text("the system default").tag("")
                ForEach(model.editors) { Text($0.name).tag($0.bundleID) }
            }
            Toggle("Launch at login", isOn: launchBinding)
            Toggle("Notify when a decoy is served", isOn: notifyBinding)
                .help("Something read a protected file with no run or consent covering it, and got fake values. "
                    + "The Decoys row and the audit show the same events.")
            Toggle("Notify when a session expires or a scan finds new cached copies", isOn: notifyChangesBinding)
                .help("A captured SSO session is about to expire or has, so the next aws call fails until you renew; "
                    + "or a whole-Mac scan found a copy of a secret in an AI agent's cache it had not seen before.")
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Protection

    /// The three settings that decide what jit hands out: how long a
    /// session stays open, whether a tool is asked about first, and
    /// whether typed credentials reach the history file.
    private var protection: some View {
        Form {
            Picker("Lock the session after", selection: ttlBinding) {
                ForEach(Self.ttls, id: \.value) { Text($0.label).tag($0.value) }
            }
            .disabled(model.settingsBusy)
            .help("Idle time before the vault locks; the next use prompts Touch ID once. Changing it restarts the service.")
            Toggle("Ask before each tool's first credential use", isOn: consentBinding)
                .disabled(model.settingsBusy || model.consentEnabled == nil)
                .help("A program reaching for a machine credential (aws, git, docker…) is shown to you first. "
                    + "Turning it off asks for Touch ID now.")
            Toggle("Keep typed credentials out of zsh history", isOn: guardBinding)
                .disabled(model.guardBusy || model.guardInstalled == nil)
                .help("A command carrying a recognized credential stays usable in that session but is never written "
                    + "to the history file. Open shells keep what they loaded until they exit.")
            if model.settingsBusy || model.guardBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Applying…").foregroundStyle(.secondary)
                }
            }
            if let message = model.settingsMessage {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Vault") {
                HStack {
                    Text("Delete every secret, keep the key")
                    Spacer()
                    Button("Clean in Terminal…", action: actions.vaultClean)
                }
                .help("jit vault clean: every secret and every backup, gone for good; the vault stays usable. jit asks once more.")
                HStack {
                    Text("Destroy the vault and its key")
                    Spacer()
                    Button("Delete in Terminal…", action: actions.vaultDelete)
                }
                .help("jit vault delete: the vault directory and the keychain item. jit asks once more.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Scan

    private var scan: some View {
        Form {
            Picker("Scan the whole Mac", selection: scheduleBinding) {
                ForEach(ScanSchedule.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            scanNote
            Section("Excluded folders") {
                if model.scanExcludes.isEmpty {
                    Text("none").foregroundStyle(.secondary)
                }
                ForEach(model.scanExcludes, id: \.self) { path in
                    HStack {
                        Text(Format.home(path)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { actions.removeExclude(path) }.buttonStyle(.link)
                    }
                }
                Button("Exclude a Folder…", action: actions.addExclude)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private var scanNote: some View {
        if model.scanSchedule == .off {
            Text("Every scan is a click.").font(.subheadline).foregroundStyle(.secondary)
        } else if model.fullDiskAccess {
            Text("Runs quietly, and again after a Protect.").font(.subheadline).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                Text("Waits for Full Disk Access.")
                Button("Grant in System Settings", action: actions.grantFullDiskAccess).buttonStyle(.link)
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var terminalBinding: Binding<String> {
        Binding(get: { model.terminalApp }, set: actions.setTerminal)
    }

    private var editorBinding: Binding<String> {
        Binding(get: { model.editorApp }, set: actions.setEditor)
    }

    private var scheduleBinding: Binding<ScanSchedule> {
        Binding(get: { model.scanSchedule }, set: actions.setScanSchedule)
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

    /// jit's verdict, never the app's: the toggle reads `status.guard.installed`
    /// after each change, so a source line disabled by hand reads as off.
    private var notifyBinding: Binding<Bool> {
        Binding(get: { model.notifyDecoys }, set: actions.setNotifyDecoys)
    }

    private var notifyChangesBinding: Binding<Bool> {
        Binding(get: { model.notifyChanges }, set: actions.setNotifyChanges)
    }

    private var guardBinding: Binding<Bool> {
        Binding(get: { model.guardInstalled ?? false }, set: actions.setGuard)
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
    var setScanSchedule: (ScanSchedule) -> Void = { _ in }
    var grantFullDiskAccess: () -> Void = {}
    var setTTL: (String) -> Void = { _ in }
    var setConsent: (Bool) -> Void = { _ in }
    var setGuard: (Bool) -> Void = { _ in }
    var setNotifyDecoys: (Bool) -> Void = { _ in }
    var setNotifyChanges: (Bool) -> Void = { _ in }
    var vaultClean: () -> Void = {}
    var vaultDelete: () -> Void = {}
}
