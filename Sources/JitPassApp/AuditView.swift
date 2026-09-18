// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The audit tail: the same timeline `jit audit` prints, with its filters
/// as controls, reloaded on every session event the stream delivers while
/// the window is open. Read-only; the terminal keeps the full record.
struct AuditView: View {
    @ObservedObject var model: MenuModel
    let actions: AuditActions

    /// The CLI's kind values, and what each means to a reader. The value is
    /// what `--kind` takes; the label is what the picker and the row show.
    private static let kinds: [(value: String, label: String)] = [
        ("cmd", "commands"), ("unlock", "unlocks"), ("use", "secret uses"), ("grant", "grants"),
        ("serve", "file reads"), ("lock", "locks"), ("service", "service"), ("error", "errors")
    ]

    /// A row's kind word: singular, and "decoy" for the read that got one.
    static func kindLabel(_ row: AuditRow) -> String {
        if row.status == "decoy" {
            return "decoy"
        }
        switch row.kind {
        case "cmd": return "command"
        case "use": return "use"
        case "serve": return "read"
        default: return row.kind
        }
    }

    private static let sinces: [(label: String, value: String)] = [
        ("last hour", "1h"), ("last 24 hours", "24h"), ("last 7 days", "7d"), ("all", "")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filters
            Divider().padding(.vertical, 8)
            if let rows = model.audit?.rows.filter({ !Self.isOwnRead($0) }) {
                if rows.isEmpty {
                    Text("Nothing matches.").foregroundStyle(.secondary).padding(.vertical, 20)
                    Spacer()
                } else {
                    list(rows)
                    if let cap = capNote(rows.count) {
                        Text(cap).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 6)
                    }
                }
            } else if model.auditLoading {
                Spacer()
            } else {
                Text("The audit log could not be read.").foregroundStyle(.secondary).padding(.vertical, 20)
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
    }

    /// The app's own bookkeeping reads (`jit status`, `jit audit`, `jit
    /// doctor`) are in the log, as every command is, but showing them here
    /// buries the events the window exists for under the act of looking,
    /// and doctor's "failed" is only its exit code for "found something".
    /// The terminal keeps them.
    static let ownReads: Set<String> = ["jit status", "jit audit", "jit doctor"]

    static func isOwnRead(_ row: AuditRow) -> Bool {
        row.kind == "cmd" && row.launchedBy == "JitPass" && ownReads.contains(row.title)
    }

    private var filters: some View {
        HStack(spacing: 10) {
            Picker("Kind", selection: kindBinding) {
                Text("all kinds").tag("")
                ForEach(Self.kinds, id: \.value) { Text($0.label).tag($0.value) }
            }
            .frame(width: 130)
            Picker("Since", selection: sinceBinding) {
                ForEach(Self.sinces, id: \.value) { Text($0.label).tag($0.value) }
            }
            .frame(width: 160)
            TextField("launched by…", text: parentBinding).textFieldStyle(.roundedBorder).frame(width: 140)
            Spacer()
            if model.auditLoading {
                ProgressView().controlSize(.small)
            }
            Button("Open in Terminal", action: actions.openInTerminal)
        }
        .labelsHidden()
    }

    /// Says when the list is the CLI's cap rather than the whole range, so
    /// "last 24 hours" ending at noon is read as a cut, not as a quiet morning.
    private func capNote(_: Int) -> String? {
        let limit = model.auditFilter.effectiveLimit
        guard limit > 0, let report = model.audit, report.commands.count + report.authEvents.count >= limit else {
            return nil
        }
        return "newest \(limit) entries shown; pick a longer range or Open in Terminal for the rest"
    }

    /// A range longer than a day puts the date on every row.
    private var spansDays: Bool {
        !["1h", "24h"].contains(model.auditFilter.since)
    }

    private func list(_ rows: [AuditRow]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Format.stamp(row.date, withDay: spansDays))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .frame(width: spansDays ? 92 : 40, alignment: .leading)
                        Text(Glyph.forRow(row)).foregroundStyle(Glyph.color(row)).frame(width: 12)
                        Text(Self.kindLabel(row)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            .frame(width: 60, alignment: .leading)
                        // The title says what happened, so the detail yields first; if the
                        // title must still be cut, cut its end, never the reader's name.
                        Text(row.title).font(.system(size: 12)).lineLimit(1).truncationMode(.tail).layoutPriority(1)
                        if !row.detail.isEmpty {
                            Text(row.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.trailing, 14)
        }
    }

    // MARK: - Bindings that reload on change

    private var kindBinding: Binding<String> {
        Binding(
            get: { model.auditFilter.kinds.first ?? "" },
            set: { value in actions.setFilter(model.auditFilter.with { $0.kinds = value.isEmpty ? [] : [value] }) }
        )
    }

    private var sinceBinding: Binding<String> {
        Binding(
            get: { model.auditFilter.since },
            set: { value in actions.setFilter(model.auditFilter.with { $0.since = value }) }
        )
    }

    private var parentBinding: Binding<String> {
        Binding(
            get: { model.auditFilter.parent },
            set: { value in actions.setFilter(model.auditFilter.with { $0.parent = value }) }
        )
    }
}

struct AuditActions {
    var setFilter: (AuditFilter) -> Void = { _ in }
    var openInTerminal: () -> Void = {}
}

/// The terminal's glyph vocabulary for the same states: ● fine, ○ needs a
/// look, ✗ act now, ✓ done.
enum Glyph {
    static func forRow(_ row: AuditRow) -> String {
        switch row.status {
        case "failed", "denied", "error": "✗"
        case "decoy", "lock": "○"
        case "ok", "approved", "unlock", "use", "grant", "serve", "real": "●"
        default: "•"
        }
    }

    static func color(_ row: AuditRow) -> Color {
        switch row.status {
        case "failed", "denied", "error": Color(StatusMark.red)
        case "decoy", "lock": Color(StatusMark.amber)
        case "ok", "approved", "unlock", "use", "grant", "serve", "real": Color(StatusMark.green)
        default: .secondary
        }
    }
}

extension AuditFilter {
    func with(_ change: (inout AuditFilter) -> Void) -> AuditFilter {
        var copy = self
        change(&copy)
        return copy
    }
}
