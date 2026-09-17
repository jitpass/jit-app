// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Add or Replace: `jit vault set <path> --stdin`. The value goes to jit
/// through a pipe, never an argument, and the only place it is visible is
/// the field the user is typing into, with the multi-line editor for keys
/// and certificates.
struct AddSecretSheet: View {
    @ObservedObject var model: MenuModel
    let actions: VaultActions
    @State var group: String
    let replacing: String?

    @State private var name = ""
    @State private var value = ""
    @State private var multiLine = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(replacing == nil ? "Add a Secret" : "Replace \(replacing ?? "")").font(.headline)
                Text(replacing == nil
                    ? "Stored encrypted under its own key. Touch ID follows."
                    : "The current value moves to history, so this is reversible. Touch ID follows.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if replacing == nil {
                SheetField("Profile") {
                    GroupComboBox(text: $group, choices: model.vaultListing?.groups.map(\.name) ?? [], placeholder: "stripe")
                }
                SheetField("Name") {
                    TextField("dev-key", text: $name).textFieldStyle(.roundedBorder)
                }
            }
            SheetField("Value") {
                if multiLine {
                    TextEditor(text: $value)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 120)
                        .border(Color.secondary.opacity(0.3))
                } else {
                    SecureField("", text: $value).textFieldStyle(.roundedBorder)
                }
                Toggle("Multi-line (a key or certificate)", isOn: $multiLine).font(.subheadline)
            }
            SheetFooter(
                model: model,
                actions: actions,
                verb: replacing == nil ? "Store with Touch ID" : "Replace with Touch ID",
                enabled: canSubmit
            ) {
                actions.set(path, value, replacing != nil)
            }
        }
        .padding(18)
        .frame(width: 480)
    }

    private var path: String {
        replacing ?? (group.trimmingCharacters(in: .whitespaces) + "/" + name.trimmingCharacters(in: .whitespaces))
    }

    private var canSubmit: Bool {
        !value.isEmpty && (replacing != nil || VaultPath.isValid(group: group, name: name))
    }
}

/// `jit vault link <path> <op://…>`: the vault stores the reference,
/// 1Password keeps the value. Verifying through `op` needs the 1Password
/// CLI where jit will look for it; without it, the link is stored as typed.
struct LinkSecretSheet: View {
    @ObservedObject var model: MenuModel
    let actions: VaultActions
    @State var group: String
    let replacing: String?

    @State private var name = ""
    @State private var reference = ""
    @State private var verify = JitCLI.onePasswordCLIInstalled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(replacing == nil ? "Link a 1Password Item" : "Relink \(replacing ?? "")").font(.headline)
                Text("Copy the reference from 1Password: field menu › Copy Secret Reference. "
                    + "Every use resolves it through the 1Password CLI at that moment.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if replacing == nil {
                SheetField("Profile") {
                    GroupComboBox(text: $group, choices: model.vaultListing?.groups.map(\.name) ?? [], placeholder: "stripe")
                }
                SheetField("Name") {
                    TextField("live", text: $name).textFieldStyle(.roundedBorder)
                }
            }
            SheetField("Reference") {
                TextField("op://Private/Stripe/credential", text: $reference)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Toggle("Verify through 1Password first", isOn: $verify)
                    .font(.subheadline)
                    .disabled(!JitCLI.onePasswordCLIInstalled)
                Text(JitCLI.onePasswordCLIInstalled
                    ? "jit's Touch ID, then 1Password's own dialog the first time."
                    : "The 1Password CLI is not installed (brew install 1password-cli), so the reference is stored as typed.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SheetFooter(model: model, actions: actions, verb: "Link with Touch ID", enabled: canSubmit) {
                actions.link(path, reference.trimmingCharacters(in: .whitespaces), verify, replacing != nil)
            }
        }
        .padding(18)
        .frame(width: 480)
    }

    private var path: String {
        replacing ?? (group.trimmingCharacters(in: .whitespaces) + "/" + name.trimmingCharacters(in: .whitespaces))
    }

    private var canSubmit: Bool {
        let ref = reference.trimmingCharacters(in: .whitespaces)
        let refOK = ref.hasPrefix("op://") && ref.split(separator: "/").count >= 4
        return refOK && (replacing != nil || VaultPath.isValid(group: group, name: name))
    }
}

/// `jit vault history`, with Restore per version. Restore archives the
/// displaced value first, so flipping between two versions loses neither.
struct HistorySheet: View {
    @ObservedObject var model: MenuModel
    let actions: VaultActions
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("History of \(path)").font(.headline)
                Text("Each overwrite keeps the outgoing value, newest five. Restoring archives the current value first.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let history = model.vaultHistory, history.path == path {
                if history.versions.isEmpty {
                    Text("No archived versions yet; history is kept from the first overwrite on.").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(history.versions) { version in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("archived " + Format.ago(version.archived))
                                    if let from = version.valueFrom {
                                        Text("value from " + Format.dateStamp(from)).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Restore") { actions.restore(path, version.stamp) }
                                    .buttonStyle(.link)
                                    .disabled(model.vaultBusy != nil)
                            }
                        }
                    }
                }
            } else {
                Text("Reading…").foregroundStyle(.secondary)
            }
            if let message = model.vaultMessage {
                Text(message).font(.subheadline).foregroundStyle(Color(StatusMark.red))
            }
            HStack {
                Spacer()
                Button("Close", action: actions.closeSheet).keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear { actions.loadHistory(path) }
    }
}

/// A labelled row in a vault sheet, the Grant sheet's layout.
struct SheetField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) { content() }
        }
    }
}

/// The error line and the Cancel / submit pair every vault sheet ends with.
struct SheetFooter: View {
    @ObservedObject var model: MenuModel
    let actions: VaultActions
    let verb: String
    let enabled: Bool
    let submit: () -> Void

    var body: some View {
        if let message = model.vaultMessage {
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(StatusMark.red).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        HStack {
            Spacer()
            Button("Cancel", action: actions.closeSheet).keyboardShortcut(.cancelAction)
            Button(model.vaultBusy == nil ? verb : "Waiting for Touch ID…", action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(!enabled || model.vaultBusy != nil)
        }
    }
}

/// What `jit vault set` accepts as a path: a group and a name, one slash
/// between them, neither empty.
enum VaultPath {
    static func isValid(group: String, name: String) -> Bool {
        let group = group.trimmingCharacters(in: .whitespaces)
        let name = name.trimmingCharacters(in: .whitespaces)
        return !group.isEmpty && !name.isEmpty && !group.contains("/") && !name.contains("/")
    }
}
