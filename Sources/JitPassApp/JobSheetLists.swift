// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

// The pieces of the New AI Job sheet that are lists or disclosures: the
// profiles jit found, the scripts in the chosen folder, and More options.
// Each is a view of its own so the sheet stays a sentence and its rows.

/// Every profile jit found on the Mac (New Grant's discovery), filterable.
/// A job takes one, so a tap picks it and the sheet moves on; a profile
/// whose secrets the vault lacks stays listed, dimmed, and says why.
struct JobProfileList: View {
    @ObservedObject var model: MenuModel
    let actions: JobSheetActions
    @State private var filter = ""

    var body: some View {
        if model.grantProfiles.isEmpty {
            Text(Format.jobNoProfiles).font(Win.rowFact).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a Folder…", action: actions.addFolder).buttonStyle(AppButton(kind: .quiet))
        } else {
            AppSearchField(placeholder: "Filter profiles", text: $filter)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(visible) { profile in
                        line(profile)
                    }
                }
                .padding(.vertical, Win.s2)
            }
            .frame(maxHeight: 5 * 46)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
            HStack(spacing: Win.s3) {
                Text(Format.grantProfilesHint(model.grantProfiles.count, matching: visible.count, filter: filter))
                    .font(Win.rowFact).foregroundStyle(.secondary)
                if filter.isEmpty {
                    Text("·").font(Win.rowFact).foregroundStyle(.secondary)
                    Button("Add a Folder…", action: actions.addFolder).buttonStyle(AppButton(kind: .plain))
                }
            }
        }
    }

    private var visible: [DiscoveredProfile] {
        let needle = filter.lowercased()
        guard !needle.isEmpty else {
            return model.grantProfiles
        }
        return model.grantProfiles.filter {
            $0.name.lowercased().contains(needle) || Format.profileFolder($0).lowercased().contains(needle)
        }
    }

    private func line(_ profile: DiscoveredProfile) -> some View {
        let broken = model.grantMissing[profile.manifestPath] ?? model.brokenProfiles[profile.name]
        return Button {
            actions.chooseProfile(profile)
        } label: {
            VStack(alignment: .leading, spacing: Win.s1) {
                HStack(spacing: Win.s3) {
                    Text(profile.name).font(Win.rowName)
                    Text(Format.profileSecrets(profile)).font(Win.command).foregroundStyle(.secondary)
                }
                HStack(spacing: Win.s3) {
                    Text(Format.profileFolder(profile)).font(Win.command).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Text(broken.map { "· " + $0 + " · see Doctor" } ?? "· " + profile.keys.joined(separator: ", "))
                        .font(Win.rowFact).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
            }
            .padding(.vertical, Win.s4).padding(.horizontal, Win.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(JobPickStyle())
        .disabled(broken != nil)
        .opacity(broken == nil ? 1 : 0.55)
        .padding(.horizontal, Win.s2)
    }
}

/// What the job runs: the scripts in its folder, each with the exact
/// command it becomes, and "Another command…" for anything else. Once one
/// is chosen it is a popup whose label is that command.
struct JobRunsPicker: View {
    @ObservedObject var model: MenuModel

    var body: some View {
        let draft = model.jobDraft
        if model.jobTyping {
            TextField("", text: $model.jobDraft.command)
                .textFieldStyle(.plain).font(Win.command).appField()
            hint(Format.jobTypingHint)
        } else if draft.argv.isEmpty {
            list
            hint(Format.jobScriptsHint(model.jobScripts, folder: draft.folder))
        } else {
            Menu {
                ForEach(model.jobScripts) { script in
                    Button(script.command) { model.jobDraft.choose(script: script) }
                }
                Divider()
                Button("Another command…") { model.jobTyping = true }
            } label: {
                HStack(spacing: Win.s4) {
                    Text(draft.command).font(Win.command).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold)).opacity(0.55)
                }
            }
            .menuStyle(.button)
            .buttonStyle(AppPopupStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            hint(Format.jobRunsHint(draft, preview: model.jobPreview))
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(model.jobScripts) { script in
                pick(name: script.file, fact: script.command, mono: true) {
                    model.jobDraft.choose(script: script)
                }
            }
            pick(name: "Another command…", fact: Format.jobTypingHint, mono: false) {
                model.jobTyping = true
            }
        }
        .padding(.vertical, Win.s2)
        .frame(maxWidth: .infinity)
        .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
    }

    private func pick(name: String, fact: String, mono: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(name).font(Win.rowName)
                Text(fact).font(mono ? Win.command : Win.rowFact).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.vertical, Win.s4).padding(.horizontal, Win.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(JobPickStyle())
        .padding(.horizontal, Win.s2)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(Win.rowFact).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// The name and the output folder, out of the way: most jobs need neither
/// changed. The closed line carries both values, so nothing that matters
/// is out of sight.
struct JobMoreOptions: View {
    @ObservedObject var model: MenuModel
    let actions: JobSheetActions

    var body: some View {
        let draft = model.jobDraft
        VStack(alignment: .leading, spacing: Win.s5) {
            HStack(spacing: Win.s5) {
                Color.clear.frame(width: 62, height: 1)
                Button {
                    model.jobMoreOptions.toggle()
                } label: {
                    HStack(spacing: Win.s3) {
                        Image(systemName: model.jobMoreOptions ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text(Format.jobMoreOptions(draft)).font(Win.sub).lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if model.jobMoreOptions {
                JobSheetRow(label: "Name") {
                    AppTextField(placeholder: "", text: nameBinding, width: 240)
                    Text(Format.jobNameHint).font(Win.rowFact).foregroundStyle(.secondary)
                }
                JobSheetRow(label: "Output") {
                    HStack(spacing: Win.s4) {
                        if draft.output.isEmpty {
                            Text("No output folder").font(Win.sub).foregroundStyle(.secondary)
                        } else {
                            Text(Format.home(draft.output)).font(Win.command).lineLimit(1).truncationMode(.head)
                        }
                        Spacer(minLength: Win.s4)
                        if !draft.output.isEmpty {
                            Button("Clear") { model.jobDraft.output = "" }.buttonStyle(AppButton(kind: .quiet))
                        }
                        Button("Choose…", action: actions.chooseOutput).buttonStyle(AppButton(kind: .quiet))
                    }
                    Text(Format.jobOutputHint).font(Win.rowFact).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Typing a name stops it following the script.
    private var nameBinding: Binding<String> {
        Binding(
            get: { model.jobDraft.name },
            set: { name in
                model.jobDraft.name = name
                model.jobDraft.nameSuggested = false
            }
        )
    }
}

/// A row that is picked by a tap: `app-hover` under the pointer, as a
/// window row, inset and rounded like the selection New Grant fills.
struct JobPickStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        JobPickHighlight(pressed: configuration.isPressed) { configuration.label }
    }
}

private struct JobPickHighlight<Label: View>: View {
    var pressed: Bool
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        label()
            .background(
                (hovering || pressed) ? WindowSurface.hover : .clear,
                in: RoundedRectangle(cornerRadius: Win.control, style: .continuous)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
    }
}
