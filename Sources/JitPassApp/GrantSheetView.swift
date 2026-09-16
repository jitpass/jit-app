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
    @State private var search = ""
    @State private var tree = false
    @State private var treeName = "claude"
    @State private var anchorPID: Int32?

    private static let durations: [(label: String, hours: Double)] = [("1h", 1), ("8h", 8), ("24h", 24), ("7d", 168)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Grant").font(.headline)
                Text("Let a program use secrets unattended, until a deadline.").font(.subheadline).foregroundStyle(.secondary)
            }

            field("Cover") {
                Picker("Cover", selection: $tree) {
                    Text("one running process").tag(false)
                    Text("any process by name, under an app").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            if tree {
                field("Name") {
                    TextField("claude", text: $treeName).textFieldStyle(.roundedBorder).frame(width: 200)
                }
                field("Under") {
                    Picker("Under", selection: $anchorPID) {
                        Text("choose a terminal or editor…").tag(Int32?.none)
                        ForEach(model.grantSessionRoots) { root in
                            Text("\(root.name) · running \(RunningProcess.age(root.elapsed))").tag(Int32?.some(root.pid))
                        }
                    }
                    .labelsHidden()
                    Text("Covers every \(treeName.isEmpty ? "process" : treeName) started under that app, now or later, for the duration.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if !tree {
                field("Process") {
                    HStack(spacing: 8) {
                        TextField("filter by name or folder", text: $search).textFieldStyle(.roundedBorder)
                        Toggle("show all", isOn: $showAll).toggleStyle(.checkbox).font(.subheadline)
                            .onChange(of: showAll) { _, all in actions.reloadProcesses(all) }
                        Button {
                            actions.reloadProcesses(showAll)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh the list")
                    }
                    processList
                }
            }

            field("Profiles") {
                if model.grantProfiles.isEmpty {
                    Text("no global profiles under ~/.jit/profiles").foregroundStyle(.secondary)
                } else {
                    profileList
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
                Text(tree ? "• every matching process under that app; ends if the app quits or at the deadline"
                    : "• that exact process only; ends when it exits or at the deadline")
                Text("• survives screen lock; revoke any time from the menu")
            }
            .font(.subheadline).foregroundStyle(.secondary)

            if let error = model.grantError {
                Text(error)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(StatusMark.red).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            HStack {
                Spacer()
                Button("Cancel", action: actions.cancel).keyboardShortcut(.cancelAction)
                Button(model.grantBusy ? "Waiting for Touch ID…" : "Grant with Touch ID") {
                    if tree, let anchorPID {
                        actions.grantTree(anchorPID, treeName, Array(profiles).sorted(), hours * 3600)
                    } else if let pid {
                        actions.grant(pid, Array(profiles).sorted(), hours * 3600)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canGrant)
            }
        }
        .padding(18)
        .frame(width: 520)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onAppear { actions.reloadProcesses(showAll) }
    }

    private var canGrant: Bool {
        guard !profiles.isEmpty, !model.grantBusy else {
            return false
        }
        return tree ? (anchorPID != nil && !treeName.isEmpty) : pid != nil
    }

    private var visibleProcesses: [RunningProcess] {
        let needle = search.lowercased()
        guard !needle.isEmpty else {
            return model.grantProcesses
        }
        return model.grantProcesses.filter { $0.name.lowercased().contains(needle) || $0.folder.lowercased().contains(needle) }
    }

    /// Two-line rows in a real list: what and where on the first line, the
    /// terminal, age and pid on the second, so two claudes are told apart
    /// by the folder they work in rather than by number.
    private var processList: some View {
        List(visibleProcesses, selection: $pid) { process in
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(process.name).fontWeight(.semibold)
                    if !process.folder.isEmpty {
                        Text(process.folder).lineLimit(1).truncationMode(.middle)
                    }
                }
                Text(Self.secondLine(process)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .tag(Int32?.some(process.pid))
        }
        .frame(height: 170)
        .scrollContentBackground(.hidden)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .overlay {
            if visibleProcesses.isEmpty {
                Text(model.grantProcesses.isEmpty ? "nothing running that jit usually grants to; try show all" : "no match")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private static func secondLine(_ process: RunningProcess) -> String {
        var parts: [String] = []
        if !process.under.isEmpty {
            parts.append("under \(process.under)")
        }
        parts.append("running \(RunningProcess.age(process.elapsed))")
        parts.append("pid \(process.pid)")
        return parts.joined(separator: " · ")
    }

    /// Checkbox rows in a bordered box that scrolls past six. A profile
    /// doctor reports as broken is shown but not offered: the agent would
    /// refuse it, and this says why before a Touch ID is spent.
    private var profileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.grantProfiles, id: \.self) { name in
                    profileRow(name)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: min(CGFloat(model.grantProfiles.count), 6) * 26 + 8)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private func profileRow(_ name: String) -> some View {
        let broken = model.brokenProfiles[name]
        return HStack(spacing: 8) {
            Toggle(name, isOn: binding(for: name)).toggleStyle(.checkbox).disabled(broken != nil)
            Spacer()
            if let broken {
                Text("✗ \(broken)").font(.system(size: 11)).foregroundStyle(Color(StatusMark.red))
            }
        }
        .frame(height: 26)
        .padding(.horizontal, 10)
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
    var grantTree: (Int32, String, [String], TimeInterval) -> Void = { _, _, _, _ in }
    var cancel: () -> Void = {}
}
