// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The question a scan carries: how far to look. Dropped from the Findings
/// window's title bar once a scope is chosen (design system, "Sheets and
/// alerts": a sheet is for a question that carries a choice). Two
/// selectable rows; selection fills the row, not a border. Deep is present
/// but not choosable until the vault holds a secret, and its row says why.
struct ScanDepthSheet: View {
    @ObservedObject var model: MenuModel
    /// nil is the whole Mac.
    let scope: String?
    let start: (ScanMode) -> Void
    let close: () -> Void

    @State private var mode: ScanMode = .regular

    private var secretsStored: Int? {
        model.cli?.vault?.secretsStored
    }

    private var deepAvailable: Bool {
        ScanMode.deepAvailable(secretsStored: secretsStored)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            Text(scope.map { "Scan " + Format.home($0) + " now" } ?? "Scan the whole Mac now").font(Win.cardTitle)
            Text("Both read only, and nothing leaves this Mac.").font(Win.rowFact).foregroundStyle(.secondary)
            VStack(spacing: Win.s1) {
                option(.regular, enabled: true)
                option(.deep, enabled: deepAvailable)
            }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Scan") { start(mode) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Win.s6)
        .frame(width: Win.sheetWide)
        // app-sheet-material: the window's own material, not macOS's default sheet.
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onAppear {
            if !deepAvailable {
                mode = .regular
            }
        }
    }

    private func option(_ candidate: ScanMode, enabled: Bool) -> some View {
        let on = mode == candidate
        return Button {
            if enabled {
                mode = candidate
            }
        } label: {
            HStack(alignment: .top, spacing: Win.s4) {
                radio(on: on, enabled: enabled)
                VStack(alignment: .leading, spacing: Win.s1) {
                    Text(candidate.name).font(Win.rowName)
                        .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    fact(candidate, enabled: enabled)
                }
                Spacer(minLength: 0)
            }
            .padding(Win.s4)
            .background(
                on ? Design.controlAccent.opacity(0.22) : .clear,
                in: RoundedRectangle(cornerRadius: Win.segment, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// The row's fact. Deep's ends in "Touch ID follows" only when the
    /// vault is locked: an unlocked service means no prompt, and saying one
    /// follows when it does not is the kind of line that teaches people to
    /// stop reading.
    private func fact(_ candidate: ScanMode, enabled: Bool) -> some View {
        let text = ScanMode.fact(candidate, secretsStored: secretsStored)
        let prompt = candidate == .deep && enabled && !isUnlocked
        let view = prompt ? Text(text) + Text(" Touch ID follows.").foregroundColor(Color(StatusMark.amber)) : Text(text)
        return view.font(Win.rowFact)
            .foregroundStyle(enabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var isUnlocked: Bool {
        if case .unlocked = model.state {
            return true
        }
        return false
    }

    private func radio(on: Bool, enabled: Bool) -> some View {
        ZStack {
            Circle().stroke(on ? Design.controlAccent : WindowSurface.controlLine, lineWidth: 1)
                .frame(width: 15, height: 15)
            if on {
                Circle().fill(Design.controlAccent).frame(width: 8, height: 8)
            }
        }
        .opacity(enabled ? 1 : 0.5)
        .padding(.top, 1)
    }
}
