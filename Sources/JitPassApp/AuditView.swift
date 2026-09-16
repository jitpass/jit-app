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

    private static let kinds = ["cmd", "unlock", "use", "grant", "serve", "lock", "service", "error"]
    private static let sinces: [(label: String, value: String)] = [
        ("last hour", "1h"), ("last 24 hours", "24h"), ("last 7 days", "7d"), ("all", "")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filters
            Divider().padding(.vertical, 8)
            if let rows = model.audit?.rows {
                if rows.isEmpty {
                    Text("Nothing matches.").foregroundStyle(.secondary).padding(.vertical, 20)
                    Spacer()
                } else {
                    list(rows)
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

    private var filters: some View {
        HStack(spacing: 10) {
            Picker("Kind", selection: kindBinding) {
                Text("all kinds").tag("")
                ForEach(Self.kinds, id: \.self) { Text($0).tag($0) }
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

    private func list(_ rows: [AuditRow]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Format.clock(row.date))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                        Text(Glyph.forRow(row)).foregroundStyle(Glyph.color(row)).frame(width: 12)
                        Text(row.kind).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                        Text(row.title).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
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
