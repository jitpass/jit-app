// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Remove JitPass window, drawn to docs/design/mockups/offboarding: the
/// setup window's twin. One fixed frame, one decision per screen, and red
/// exactly once, on the button that commits.
struct OffboardingView: View {
    @ObservedObject var model: OffboardingModel
    let actions: OffboardingActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch model.step {
                case .loading: OffboardingLoading()
                case let .unavailable(why): OffboardingUnavailable(why: why)
                case .plan: OffboardingPlanScreen(model: model)
                case .recovery: OffboardingRecovery(model: model, actions: actions)
                case .removing: OffboardingRemoving(model: model)
                case .couldNotRestore: OffboardingCouldNotRestore(model: model, actions: actions)
                case .done: OffboardingDone(model: model, actions: actions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 36)
            .padding(.top, 26)

            OffboardingFooter(model: model, actions: actions)
                .frame(height: 58)
                .padding(.horizontal, 36)
        }
        .font(.system(size: 13))
        .frame(width: OnboardingView.size.width, height: OnboardingView.size.height)
        .background(VisualEffectBackground(material: .hudWindow, cornerRadius: 0))
    }
}

private struct OffboardingFooter: View {
    @ObservedObject var model: OffboardingModel
    let actions: OffboardingActions

    private var dotIndex: Int {
        switch model.step {
        case .loading, .unavailable, .plan: 0
        case .recovery: 1
        case .removing, .couldNotRestore: 2
        case .done: 3
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0 ..< 4, id: \.self) { index in
                    Circle().fill(index == dotIndex ? Color.primary : Color.primary.opacity(0.25)).frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            Spacer()
            buttons
        }
    }

    /// The one red button. It sits on the last screen before work starts.
    @ViewBuilder
    private var removeButton: some View {
        Text("Touch ID follows.").font(.system(size: 12)).foregroundStyle(.secondary)
        Button(model.restoring ? "Remove JitPass" : "Remove Without Restoring", action: actions.remove)
            .buttonStyle(.borderedProminent).tint(.red)
    }

    @ViewBuilder private var buttons: some View {
        switch model.step {
        case .loading:
            Button("Cancel", action: actions.cancel).keyboardShortcut(.cancelAction)
        case .unavailable:
            Button("Close", action: actions.cancel).keyboardShortcut(.defaultAction)
        case .plan:
            Button("Cancel", action: actions.cancel).keyboardShortcut(.cancelAction)
            if model.restoring, !model.plan.vaultOnly.isEmpty {
                Button("Continue", action: actions.next).keyboardShortcut(.defaultAction)
            } else {
                removeButton
            }
        case .recovery:
            if model.recoveryBusy {
                ProgressView().controlSize(.small)
            }
            Button("Back", action: actions.back).disabled(model.recoveryBusy)
            removeButton.disabled(model.recoveryBusy)
        case .removing:
            if model.stopped != nil {
                Button("Close", action: actions.cancel)
                Button("Try Again", action: actions.tryAgain).keyboardShortcut(.defaultAction)
            } else {
                Text("This window stays open until it is safe to close.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .couldNotRestore:
            Button("Remove Anyway…", action: actions.removeAnyway).buttonStyle(.link).font(.system(size: 12))
            Button("Keep JitPass", action: actions.cancel)
            Button("Try Again", action: actions.tryAgain).keyboardShortcut(.defaultAction)
        case .done:
            Button(model.homebrew ? "Copy and Quit" : "Move to Trash and Quit", action: actions.finish)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct OffboardingLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remove JitPass from this Mac").font(.system(size: 22, weight: .bold))
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading what JitPass changed. Nothing is touched.").foregroundStyle(.secondary)
            }
        }
    }
}

private struct OffboardingUnavailable: View {
    let why: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remove is not available").font(.system(size: 22, weight: .bold))
            Text(why).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}

/// One group of the plan: a dot, what happens, a count, and the paths.
private struct OffboardingGroup: View {
    let tint: Color
    let title: String
    let detail: String
    let paths: [String]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(tint).frame(width: 9, height: 9).padding(.top, 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(.semibold)
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if !paths.isEmpty {
                    Button(open ? "Hide" : "Show") { open.toggle() }.buttonStyle(.link).font(.system(size: 12))
                }
            }
            if open {
                ScrollView {
                    Text(paths.map(Format.home).joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(maxHeight: 84)
                .padding(.leading, 21)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
    }
}

private struct OffboardingPlanScreen: View {
    @ObservedObject var model: OffboardingModel

    private var plan: UninstallPlan {
        model.plan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remove JitPass from this Mac").font(.system(size: 22, weight: .bold))
            Text("Nothing has changed yet. This is what Remove does, in this order.").foregroundStyle(.secondary)
            VStack(spacing: 0) {
                if model.restoring {
                    OffboardingGroup(
                        tint: .primary, title: filesTitle, detail: filesDetail, paths: plan.restore.map(\.path)
                    )
                } else {
                    OffboardingGroup(
                        tint: Color(StatusMark.amber), title: "Nothing can be put back",
                        detail: "The vault's key is missing from the keychain, so its \(plan.secrets) secrets cannot be read. "
                            + "A recovery file brings them back: close this and use Restore. Removing now deletes them.",
                        paths: []
                    )
                }
                Divider().padding(.horizontal, 14)
                if model.restoring, !plan.vaultOnly.isEmpty {
                    OffboardingGroup(
                        tint: Color(StatusMark.amber), title: lostTitle,
                        detail: OffboardingPlan.describe(vaultOnly: plan.vaultOnly) + ". Without a recovery file they are gone.",
                        paths: plan.vaultOnly.map(\.path)
                    )
                    Divider().padding(.horizontal, 14)
                }
                OffboardingGroup(
                    tint: Color.primary.opacity(0.4), title: "Everything JitPass installed is removed",
                    detail: removedDetail, paths: plan.projectStores + plan.helpers
                )
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
            if let note = leftNote {
                Text(note).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("What this runs", isExpanded: $model.showsCommands) {
                Text("jit " + model.command.filter { $0 != "--format" && $0 != "ndjson" }.joined(separator: " "))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .font(.system(size: 12))
        }
    }

    private var filesTitle: String {
        switch plan.restore.count {
        case 0: "No files to put back"
        case 1: "1 file goes back to a plain file"
        default: "\(plan.restore.count) files go back to plain files"
        }
    }

    private var filesDetail: String {
        var text = "Their secrets are written back, readable by anything on this Mac, as before JitPass."
        let drifted = plan.drifted.count
        if drifted > 0 {
            text += drifted == 1
                ? " 1 changed since; today's version is kept beside it."
                : " \(drifted) changed since; today's version is kept beside each."
        }
        return text
    }

    private var lostTitle: String {
        plan.vaultOnly.count == 1 ? "1 secret has no file to go back to" : "\(plan.vaultOnly.count) secrets have no file to go back to"
    }

    private var removedDetail: String {
        var parts = ["The vault and its key", "the background service"]
        if !plan.shims.isEmpty {
            parts.append("protection for " + plan.shims.prefix(3).joined(separator: ", ") + (plan.shims.count > 3 ? " and more" : ""))
        }
        if plan.historyGuard || plan.pathLineFile != nil {
            parts.append("JitPass's lines in your shell config")
        }
        parts.append("settings and permissions")
        return parts.joined(separator: ", ") + "."
    }

    /// What Remove deliberately leaves as it is, said once.
    private var leftNote: String? {
        var notes: [String] = []
        if !plan.keptClean.isEmpty {
            notes.append("Tokens JitPass cleaned out of your shell history and AI caches stay cleaned.")
        }
        if !plan.gone.isEmpty {
            let count = plan.gone.count
            notes
                .append(count == 1 ? "1 migrated file you have since deleted is not recreated." :
                    "\(count) migrated files you have since deleted are not recreated.")
        }
        if !plan.unwired.isEmpty {
            notes.append("\(plan.unwired.map(Format.home).joined(separator: ", ")) no longer has JitPass's line and is left alone.")
        }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }
}

private struct OffboardingRecovery: View {
    @ObservedObject var model: OffboardingModel
    let actions: OffboardingActions

    var body: some View {
        let count = model.plan.vaultOnly.count
        VStack(alignment: .leading, spacing: 14) {
            Text(count == 1 ? "Keep a copy of that secret?" : "Keep a copy of those \(count)?").font(.system(size: 22, weight: .bold))
            Text(
                "They exist only in the vault. A recovery file holds every secret, locked with a passphrase you choose. "
                    + "A future JitPass can restore from it."
            )
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Save a recovery file").fontWeight(.semibold)
                    Text(detail).font(.system(size: 12)).foregroundStyle(detailTint).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(model.recoverySaved == nil ? "Save…" : "Save Again…", action: actions.saveRecovery).disabled(model.recoveryBusy)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
            if model.recoverySaved == nil {
                Text(count == 1 ? "Without it that secret is gone for good." : "Without it those \(count) secrets are gone for good.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String {
        if let error = model.recoveryError {
            return error
        }
        if let saved = model.recoverySaved {
            return "Saved to \(Format.home(saved)). Keep the passphrase: nobody can reset it."
        }
        return "Touch ID follows, then a place and a passphrase."
    }

    private var detailTint: Color {
        model.recoveryError == nil ? .secondary : Color(StatusMark.amber)
    }
}

private struct OffboardingRemoving: View {
    @ObservedObject var model: OffboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.stopped == nil ? "Removing JitPass" : "Removal stopped").font(.system(size: 22, weight: .bold))
            Text(model.stopped ?? "Files come back first. Nothing is deleted until every one of them is in place.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.tasks) { task in
                    OnboardingTaskRow(task: task)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
        }
    }
}
