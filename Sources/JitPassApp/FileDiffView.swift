// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Show Changes in the AI job review: the file's change since git's last
/// commit, as a title, one sentence and the diff (the result-sheets
/// mockup, section 6). A diff is code, so it stays monospaced, but it is
/// drawn as a diff: line numbers, a green wash on added lines and a red one
/// on removed lines, each hunk a quiet "lines 12–16" label. No difference
/// and a failure are the sentence alone, with no box.
struct FileDiffView: View {
    let diff: FileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s4) {
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(diff.title).font(Win.cardTitle)
                Text(diff.sentence).font(Win.sub).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !diff.lines.isEmpty {
                // Vertical only, and a long line wraps under its own text:
                // a horizontal scroll sized each row to its text, so the
                // green and red stopped short of the box's edge.
                ScrollView {
                    // Lazy: up to 2,000 rows, drawn as they scroll in.
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diff.lines) { line in
                            row(line)
                        }
                    }
                    .padding(.vertical, Win.s3)
                }
                .frame(maxHeight: Design.Sheet.listMax)
                .fixedSize(horizontal: false, vertical: true)
                .background(WindowSurface.verbatim, in: RoundedRectangle(cornerRadius: Win.control, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ line: FileDiff.Line) -> some View {
        // Every column holds at least a space: an empty Text has no
        // baseline, and the row it sat in drew taller than its neighbours.
        HStack(alignment: .firstTextBaseline, spacing: Win.s3) {
            // Each column as wide as its widest content (the longest line
            // number, one sign), so every row's text starts in one place.
            ZStack(alignment: .trailing) {
                Text(widestNumber).hidden()
                Text(line.number.map(String.init) ?? " ").foregroundStyle(.tertiary)
            }
            ZStack {
                Text("+").hidden()
                Text(sign(line.kind)).foregroundStyle(signColor(line.kind))
            }
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(textStyle(line.kind))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Win.command)
        .padding(.horizontal, Win.s4)
        .padding(.vertical, Win.s1 / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(wash(line.kind))
        .textSelection(.enabled)
    }

    private var widestNumber: String {
        String(repeating: "0", count: String(diff.lines.compactMap(\.number).max() ?? 0).count)
    }

    private func sign(_ kind: FileDiff.Kind) -> String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        default: " "
        }
    }

    private func signColor(_ kind: FileDiff.Kind) -> Color {
        switch kind {
        case .added: Color(StatusMark.green)
        case .removed: Color(StatusMark.red)
        default: .secondary
        }
    }

    private func textStyle(_ kind: FileDiff.Kind) -> HierarchicalShapeStyle {
        switch kind {
        case .added, .removed: .primary
        case .hunk, .note: .tertiary
        case .context: .secondary
        }
    }

    private func wash(_ kind: FileDiff.Kind) -> Color {
        switch kind {
        case .added: Color(StatusMark.diffAdded)
        case .removed: Color(StatusMark.diffRemoved)
        default: .clear
        }
    }
}
