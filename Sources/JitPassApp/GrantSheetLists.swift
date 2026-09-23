// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

// The two lists inside the New Grant sheet: the running processes (one
// process cover) and every profile on the Mac. Each is a view of its own
// so the sheet stays a sentence and its rows.

/// The running processes, filtered by name or folder, the usual ones or
/// all of them. A tap picks one; the picked row fills `accent-dim`.
struct GrantProcessList: View {
    @ObservedObject var model: MenuModel
    @Binding var draft: GrantDraft
    @State private var filter = ""
    @State private var showAll = false

    var body: some View {
        HStack(spacing: Win.s4) {
            AppSearchField(placeholder: "Filter by name or folder", text: $filter)
            AppSegmented(
                items: [
                    AppSegmentItem(value: false, title: "Usual", count: model.grantProcesses.count),
                    AppSegmentItem(value: true, title: "All", count: model.grantAllProcesses.count)
                ],
                selection: $showAll
            )
        }
        ScrollView {
            VStack(spacing: 0) {
                ForEach(visible) { process in
                    line(process)
                }
            }
            .padding(.vertical, Win.s2)
        }
        .frame(height: 170)
        .frame(maxWidth: .infinity)
        .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
        .overlay {
            if visible.isEmpty {
                Text(filter.isEmpty ? "Nothing running that jit usually grants to. Try All." : "No match.")
                    .font(Win.sub).foregroundStyle(.secondary)
            }
        }
    }

    private var visible: [RunningProcess] {
        let source = showAll ? model.grantAllProcesses : model.grantProcesses
        let needle = filter.lowercased()
        guard !needle.isEmpty else {
            return source
        }
        return source.filter { $0.name.lowercased().contains(needle) || $0.folder.lowercased().contains(needle) }
    }

    private func line(_ process: RunningProcess) -> some View {
        let selected = draft.pid == process.pid
        return Button {
            draft.pid = process.pid
            draft.processName = process.name
        } label: {
            VStack(alignment: .leading, spacing: Win.s1) {
                HStack(spacing: Win.s3) {
                    Text(process.name).font(Win.rowName)
                    if !process.folder.isEmpty {
                        Text("· " + process.folder).font(Win.command).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Text(Format.processFact(process)).font(Win.rowFact).foregroundStyle(.secondary)
            }
            .padding(.vertical, Win.s4).padding(.horizontal, Win.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? GrantSheetView.selection : .clear, in: RoundedRectangle(cornerRadius: Win.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Win.s2)
    }
}

/// Every profile jit found, filterable, each with its key names and the
/// folder that tells two apart. A profile doctor reports as broken stays
/// in the list, dimmed, and says why; it cannot be ticked.
struct GrantProfileList: View {
    @ObservedObject var model: MenuModel
    @Binding var draft: GrantDraft
    let actions: GrantActions
    @State private var filter = ""

    var body: some View {
        if model.grantProfiles.isEmpty {
            empty
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
                    Button("Add a Folder…", action: actions.chooseFolder).buttonStyle(AppButton(kind: .plain))
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
        let on = draft.profiles.contains(profile)
        return HStack(alignment: .top, spacing: Win.s5) {
            Toggle("", isOn: Binding(
                get: { on },
                set: { tick in
                    if tick, !on {
                        draft.profiles.append(profile)
                    } else if !tick {
                        draft.profiles.removeAll { $0 == profile }
                    }
                }
            ))
            .toggleStyle(.checkbox).labelsHidden().padding(.top, 1)
            .disabled(broken != nil)
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
            Spacer(minLength: 0)
        }
        .padding(.vertical, Win.s4).padding(.horizontal, Win.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(on ? GrantSheetView.selection : .clear, in: RoundedRectangle(cornerRadius: Win.control, style: .continuous))
        .opacity(broken == nil ? 1 : 0.55)
        .padding(.horizontal, Win.s2)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Win.s3) {
            HStack(alignment: .top, spacing: Win.s5) {
                VStack(alignment: .leading, spacing: Win.s1) {
                    Text(Format.grantProfilesEmptyTitle).font(Win.cardTitle)
                    Text(Format.grantProfilesEmptyNote).font(Win.cardNote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Win.s5)
                Button("Open Findings…", action: actions.openFindings).buttonStyle(AppButton(kind: .quiet))
            }
            .padding(.vertical, Win.s4).padding(.horizontal, Win.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
            Text(Format.grantProfilesEmptyHint).font(Win.rowFact).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
