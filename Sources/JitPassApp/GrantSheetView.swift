// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// New Grant: pick a running process, the profiles it may use, and for how
/// long. The decision itself is the agent's disclosed Touch ID, which names
/// the process and the profiles from its own facts; this sheet only
/// collects the request, exactly as `jit grant --pid` does.
struct GrantSheetView: View {
    @ObservedObject var model: MenuModel
    let actions: GrantActions

    @State private var pid: Int32?
    @State private var profiles: Set<String> = []
    @State private var hours: Double = 8
    @State private var showAll = false

    private static let durations: [(label: String, hours: Double)] = [("1h", 1), ("8h", 8), ("24h", 24), ("7d", 168)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Grant").font(.headline)
                Text("Let a program use secrets unattended, until a deadline.").font(.subheadline).foregroundStyle(.secondary)
            }

            field("Process") {
                Picker("Process", selection: $pid) {
                    Text("choose…").tag(Int32?.none)
                    ForEach(model.grantProcesses) { Text($0.label).tag(Int32?.some($0.pid)) }
                }
                .labelsHidden()
                Toggle("show all", isOn: $showAll).toggleStyle(.checkbox).font(.subheadline)
                    .onChange(of: showAll) { _, all in actions.reloadProcesses(all) }
            }

            field("Profiles") {
                if model.grantProfiles.isEmpty {
                    Text("no global profiles under ~/.jit/profiles").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(model.grantProfiles, id: \.self) { name in
                                Toggle(name, isOn: binding(for: name)).toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }

            field("For") {
                Picker("For", selection: $hours) {
                    ForEach(Self.durations, id: \.hours) { Text($0.label).tag($0.hours) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("• covers the chosen profiles' secrets as they are now")
                Text("• that exact process only; ends when it exits or at the deadline")
                Text("• survives screen lock; revoke any time from the menu")
            }
            .font(.subheadline).foregroundStyle(.secondary)

            if let error = model.grantError {
                Text(error).font(.subheadline).foregroundStyle(Color(StatusMark.red))
            }

            HStack {
                Spacer()
                Button("Cancel", action: actions.cancel).keyboardShortcut(.cancelAction)
                Button(model.grantBusy ? "Waiting for Touch ID…" : "Grant with Touch ID") {
                    guard let pid else {
                        return
                    }
                    actions.grant(pid, Array(profiles).sorted(), hours * 3600)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pid == nil || profiles.isEmpty || model.grantBusy)
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onAppear { actions.reloadProcesses(showAll) }
    }

    private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) { content() }
        }
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { profiles.contains(name) },
            set: { on in
                if on {
                    profiles.insert(name)
                } else {
                    profiles.remove(name)
                }
            }
        )
    }
}

struct GrantActions {
    var reloadProcesses: (Bool) -> Void = { _ in }
    var grant: (Int32, [String], TimeInterval) -> Void = { _, _, _ in }
    var cancel: () -> Void = {}
}
