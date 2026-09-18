// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The two screens Remove JitPass can end on.
struct OffboardingCouldNotRestore: View {
    @ObservedObject var model: OffboardingModel
    let actions: OffboardingActions

    var body: some View {
        let count = model.failures.count
        VStack(alignment: .leading, spacing: 14) {
            Text(count == 1 ? "1 file could not be put back" : "\(count) files could not be put back")
                .font(.system(size: 22, weight: .bold))
            Text(
                "So nothing was deleted. The vault, its key and every secret are still here. "
                    + "Files that did come back stay as they are."
            )
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.failures) { failure in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).frame(width: 18, height: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Format.home(failure.path)).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                                Text(failure.error).font(.system(size: 12)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Button("Show") { actions.show(failure.path) }.buttonStyle(.link).font(.system(size: 12))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxHeight: 210)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
            Text("Fix these and try again, or remove anyway: those files stay as they are now, without their secrets.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OffboardingDone: View {
    @ObservedObject var model: OffboardingModel
    let actions: OffboardingActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(Color(StatusMark.green))
                Text("This Mac is as it was").font(.system(size: 22, weight: .bold))
            }
            Text(summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider().padding(.horizontal, 14)
                        }
                        HStack(alignment: .top, spacing: 12) {
                            Text(row.0)
                            Spacer(minLength: 8)
                            Text(row.1).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
            }
            ForEach(model.problems, id: \.self) { problem in
                Text(problem).font(.system(size: 12)).foregroundStyle(Color(StatusMark.amber)).fixedSize(horizontal: false, vertical: true)
            }
            lastStep
            Text("Install JitPass again any time. It starts from the beginning.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        let count = model.restoring ? model.plan.restore.count : 0
        let held = count == 1 ? "1 file holds its secrets" : "\(count) files hold their secrets"
        let files = count == 0 ? "" : held + " as plain text again. "
        return files + "Nothing of JitPass is running, stored or referenced, except this app."
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = []
        if let saved = model.recoverySaved {
            rows.append(("Recovery file", Format.home(saved)))
        }
        if model.restoring, !model.plan.drifted.isEmpty {
            rows.append((
                "Today's versions, kept",
                model.plan.drifted.map { Format.home($0.path) + ".before-jitpass-removal" }.joined(separator: "\n")
            ))
        }
        rows.append(("Open terminal windows", "keep the old PATH until closed"))
        if let other = model.otherJit {
            rows.append(("Another jit, not this app's", Format.home(other)))
        }
        return rows
    }

    @ViewBuilder private var lastStep: some View {
        if model.homebrew {
            VStack(alignment: .leading, spacing: 6) {
                Text("One step is left: Homebrew installed this app").fontWeight(.semibold)
                Text("It also owns the jit command and its completions. This removes all of them:")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(OffboardingFinish.brewCommand)
                    .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.opacity(0.25)))
            }
        } else {
            Text("One step is left, and it is yours: the app cannot remove itself while it runs.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

enum OffboardingFinish {
    static let brewCommand = "brew uninstall --cask jitpass"
}
