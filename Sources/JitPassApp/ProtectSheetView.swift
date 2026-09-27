// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Protect's question, with the split (the "Secrets-Only Vault" mockup,
/// section 1): one card per file, what goes to the vault and what stays,
/// each line movable. jit decided each line (`jit migrate preview`); a
/// line the user moves goes back as a flag. Secrets are dots: their values
/// never reach this process. Settings show their values, which are plain
/// text on disk already (D3).
struct ProtectSheetView: View {
    @State var split: ProtectSplit
    let wraps: [String]
    let home: String
    /// Said before the split: "This Mac has no vault yet, so this creates
    /// one first."
    let lead: String?
    /// What the agent-cache sweep will reach, from the scan on screen.
    let sweep: String?
    let finish: (ProtectSplit?) -> Void

    /// Files whose lines are open. A card with a line to check opens on its
    /// own; the rest stay closed until asked.
    @State private var open: Set<String> = []
    @State private var allSettings: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(ScanWording.protectSheetTitle(split, home: home, wraps: wraps)).font(Win.cardTitle)
                Text(sentence).font(Win.sub).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            CappedScroll(maxHeight: 560) {
                VStack(alignment: .leading, spacing: Win.s4) {
                    ForEach(split.preview.files, id: \.path) { card($0) }
                    ForEach(wraps, id: \.self) { tool in
                        AppPlainCard {
                            AppRow(name: "The " + tool + " command", fact: "It gets its key from the vault when it runs.", last: true) {}
                        }
                    }
                }
            }
            HStack(spacing: Win.s4) {
                Text("Touch ID follows.").font(Win.sub).foregroundStyle(.secondary)
                Spacer(minLength: Win.s5)
                Button("Cancel") { finish(nil) }.buttonStyle(AppButton()).keyboardShortcut(.cancelAction)
                Button("Protect") { finish(split) }.buttonStyle(AppButton(kind: .primary)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Win.s6)
        .frame(width: Win.sheetWide)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onAppear {
            open = Set(split.envFiles.filter { split.counts($0).check > 0 }.map(\.path))
        }
    }

    private var sentence: String {
        var parts: [String] = []
        if let lead {
            parts.append(lead)
        }
        let split = ScanWording.protectSheetSentence(split)
        if !split.isEmpty {
            parts.append(split)
        }
        parts.append("Each file keeps working and is backed up first.")
        if let sweep {
            parts.append(sweep)
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private func card(_ file: MigratePreview.File) -> some View {
        let url = URL(fileURLWithPath: file.path)
        let place = Format.home(url.deletingLastPathComponent().path)
        switch file.kind {
        case "env":
            let counts = split.counts(file)
            let isOpen = open.contains(file.path)
            AppPlainCard {
                AppRow(name: url.lastPathComponent, detail: place, fact: ScanWording.protectCardNote(counts), last: !isOpen) {
                    Button(isOpen ? "Hide Lines" : "Show Lines") { toggle(file.path) }.buttonStyle(AppButton(kind: .plain))
                }
                if isOpen {
                    lines(file)
                }
            }
        case "mcp":
            let mcp = file.mcp
            AppPlainCard {
                AppRow(
                    dot: mcp?.covered == true ? Color(StatusMark.green) : nil,
                    name: url.lastPathComponent,
                    detail: place,
                    fact: mcp.map { $0.covered ? ScanWording.protectCoveredNote($0, home: home) : "Its secrets move to the vault." },
                    wraps: true,
                    last: true
                ) {}
            }
        default:
            AppPlainCard {
                AppRow(name: url.lastPathComponent, detail: place, fact: "Its secret moves to the vault.", last: true) {}
            }
        }
    }

    /// The vault's lines first, then the settings, folded past the first two.
    @ViewBuilder
    private func lines(_ file: MigratePreview.File) -> some View {
        let vars = file.vars ?? []
        let vaulted = vars.filter { split.inVault(file: file.path, variable: $0) }
        let kept = vars.filter { !split.inVault(file: file.path, variable: $0) }
        let showAll = allSettings.contains(file.path) || kept.count <= 3
        let keptShown = showAll ? kept : Array(kept.prefix(2))
        if !vaulted.isEmpty {
            group("Goes to the vault")
            ForEach(vaulted, id: \.name) { line(file, $0, last: kept.isEmpty && $0 == vaulted.last) }
        }
        if !kept.isEmpty {
            HStack(spacing: Win.s3) {
                group("Stays as it is · " + (kept.count == 1 ? "1 setting" : "\(kept.count) settings"))
                Spacer()
                if kept.count > 3 {
                    Button(showAll ? "Show Fewer" : "Show All") { toggleAll(file.path) }.buttonStyle(AppButton(kind: .plain))
                }
            }
            ForEach(keptShown, id: \.name) { line(file, $0, last: showAll && $0 == kept.last) }
            if !showAll {
                Text(kept.dropFirst(2).map(\.name).prefix(3).joined(separator: ", ")
                    + (kept.count > 5 ? " and \(kept.count - 5) more" : ""))
                    .font(Win.rowFact).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Win.s4).padding(.horizontal, Win.s3)
            }
        }
    }

    private func group(_ title: String) -> some View {
        Text(title).font(Win.eyebrow).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Win.s4).padding(.horizontal, Win.s3)
    }

    private func line(_ file: MigratePreview.File, _ variable: MigratePreview.Var, last: Bool) -> some View {
        let inVault = split.inVault(file: file.path, variable: variable)
        let fact: String? = variable.varClass == "check" && inVault
            ? "Check this · the name says secret; the value doesn't look like one"
            : nil
        return AppRow(name: variable.name, fact: fact, wraps: fact != nil, last: last) {
            Text(inVault ? "••••••••" : (variable.value ?? ""))
                .font(Win.command).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: 150, alignment: .trailing)
            AppSegmented(
                items: [AppSegmentItem(value: true, title: "Vault"), AppSegmentItem(value: false, title: "Setting")],
                selection: Binding(
                    get: { split.inVault(file: file.path, variable: variable) },
                    set: { split.set(file: file.path, variable: variable, inVault: $0) }
                )
            )
            // Its words never wrap: the value beside it gives way first.
            .fixedSize()
        }
    }

    private func toggle(_ path: String) {
        if open.contains(path) {
            open.remove(path)
        } else {
            open.insert(path)
        }
    }

    private func toggleAll(_ path: String) {
        if allSettings.contains(path) {
            allSettings.remove(path)
        } else {
            allSettings.insert(path)
        }
    }
}
