// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The setup window's second half: what the scan found, the live protect
/// checklist, and the closing number.
struct OnboardingResults: View {
    @ObservedObject var model: OnboardingModel
    let actions: OnboardingActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = model.scanError {
                Text("The scan did not finish").font(.system(size: 22, weight: .bold))
                Text(error).foregroundStyle(.secondary)
            } else if let report = model.report {
                found(report)
            }
        }
        .font(.system(size: 13))
    }

    @ViewBuilder private func found(_ report: ScanReport) -> some View {
        let s = report.summary
        OnboardingHeadline(
            number: "\(model.exposed)",
            label: model.exposed == 1 ? "secret in plain text" : "secrets in plain text",
            trailing: "\(s.percent)% protected", tint: .primary
        )
        OnboardingBar(percent: s.percent)
        if model.exposed == 0 {
            Text("Nothing exposed in the places we looked.").fontWeight(.semibold)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                bullet(StatusMark.green, "JitPass can protect \(s.secretsMigratable) right now", planSummary)
                if s.secretsManual > 0 {
                    bullet(StatusMark.amber, "\(s.secretsManual) need you", "rotate or remove; we show you how after")
                }
            }
            Divider()
            files(report)
        }
        if model.onePasswordInstalled, !model.tasks.isEmpty, s.secretsMigratable > 0 {
            Toggle(isOn: $model.linkOnePassword) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Link values that already live in 1Password").font(.system(size: 12))
                    Text("Slower: 1Password asks to authorise, then every item is read. A large account adds minutes.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
        }
        if let skipped = model.notScanned {
            HStack {
                Text(skipped).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Include them…", action: actions.fullScan).buttonStyle(.link).font(.system(size: 12))
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
        }
    }

    private var planSummary: String {
        let plan = model.report?.protectPlan ?? ProtectPlan()
        var parts: [String] = []
        if !plan.migrate.isEmpty {
            parts.append(plan.migrate.count == 1 ? "1 file" : "\(plan.migrate.count) files")
        }
        if !plan.wrap.isEmpty {
            parts.append(plan.wrap.count == 1 ? "1 tool" : "\(plan.wrap.count) tools")
        }
        return parts.joined(separator: ", ")
    }

    private func bullet(_ color: NSColor, _ text: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(Color(color)).frame(width: 8, height: 8)
            Text(text).fontWeight(.semibold)
            Text(detail).foregroundStyle(.secondary)
        }
    }

    /// The first few files, worst first; the Scan window keeps the full list.
    private func files(_ report: ScanReport) -> some View {
        let groups = ScanFileGroup.group(report.migratable + report.manual)
        let shown = Array(groups.prefix(4))
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(shown) { group in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Severity.color(group.severity)).frame(width: 7, height: 7)
                    Text(Format.home(group.filePath)).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(group.findings.first.map { Format.findingType($0.findingType) } ?? "")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if groups.count > shown.count {
                Text("… \(groups.count - shown.count) more files").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

struct OnboardingProtecting: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.failedTask == nil ? "Protecting your secrets" : "One step did not finish")
                .font(.system(size: 22, weight: .bold))
            Text("Every file is backed up, encrypted, before it is touched. You can undo all of it.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(model.tasks) { task in
                    OnboardingTaskRow(task: task)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
            Text(
                "macOS will show “Background Items Added”. That is JitPass’s service, "
                    + "the part that lets one fingerprint last a few minutes."
            )
            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("What this runs", isExpanded: $model.showsCommands) {
                Text(OnboardingPlan.commandLines(model.tasks, home: NSHomeDirectory()).joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(4).textSelection(.enabled)
            }
            .font(.system(size: 12))
        }
        .font(.system(size: 13))
    }
}

struct OnboardingTaskRow: View {
    let task: OnboardingTask

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon.frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title).fontWeight(.semibold).foregroundStyle(task.state == .pending ? .secondary : .primary)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if case let .failed(why) = task.state {
            return why
        }
        return task.detail
    }

    @ViewBuilder private var icon: some View {
        switch task.state {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(StatusMark.green))
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color(StatusMark.amber))
        }
    }
}

struct OnboardingDone: View {
    @ObservedObject var model: OnboardingModel
    let actions: OnboardingActions

    var body: some View {
        let s = model.report?.summary
        VStack(alignment: .leading, spacing: 12) {
            OnboardingHeadline(
                number: "\(s?.percent ?? 0)%", label: "protected",
                trailing: "\(s?.secretsProtected ?? 0) of \(s?.secretsTotal ?? 0) secrets in the vault", tint: Color(StatusMark.green)
            )
            OnboardingBar(percent: s?.percent ?? 0)
            Text(
                "Your tools work as before. macOS asks for Touch ID about once per 5 minutes of use. "
                    + "Open a new terminal window to pick up the change."
            )
            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switches
            ForEach(model.finishProblems, id: \.self) { problem in
                Text(problem).font(.system(size: 12)).foregroundStyle(Color(StatusMark.amber))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 13))
    }

    private var switches: some View {
        VStack(spacing: 0) {
            OnboardingFinishRow(
                title: "Save a recovery file",
                detail: model.recoverySaved.map { "Saved to \(Format.home($0)). Keep the passphrase: nobody can reset it." }
                    ?? "Your vault opens only on this Mac. A file and a passphrase bring it back on a new one."
            ) {
                if model.finishBusy == "recovery" {
                    ProgressView().controlSize(.small)
                } else if model.recoverySaved != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(StatusMark.green))
                } else {
                    Button("Save…", action: actions.saveRecovery)
                }
            }
            Divider()
            OnboardingFinishRow(title: "Open JitPass at login", detail: "So protection is there after a restart.") {
                Toggle("Open JitPass at login", isOn: $model.launchAtLogin).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            OnboardingFinishRow(
                title: "Tell me when something reads a protected file",
                detail: "macOS will ask to allow notifications."
            ) {
                Toggle("Notifications", isOn: $model.notify).labelsHidden().toggleStyle(.switch)
            }
            if model.offersGuard {
                Divider()
                OnboardingFinishRow(title: "Keep secrets out of shell history", detail: "Adds one line to ~/.zshrc.") {
                    Toggle("History guard", isOn: $model.historyGuard).labelsHidden().toggleStyle(.switch)
                }
            }
            if model.offersCLI {
                Divider()
                OnboardingFinishRow(title: "Use jit in Terminal", detail: "Links the jit command into your PATH.") {
                    Toggle("Command line tool", isOn: $model.installCLI).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
        .disabled(model.finishBusy != nil)
    }
}

private struct OnboardingFinishRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            control()
        }
        .padding(.vertical, 8)
    }
}

struct OnboardingRestore: View {
    @ObservedObject var model: OnboardingModel
    let actions: OnboardingActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                StatusMarkView(state: .notRunning, needsSetup: true, size: 40)
                Text("Restore").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            Text(model.strandedSecrets > 0 ? "This Mac has a vault it cannot open" : "Bring your vault to this Mac")
                .font(.system(size: 22, weight: .bold))
            Text(explanation).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Recovery file").font(.system(size: 12, weight: .semibold))
                HStack(spacing: 8) {
                    Text(model.restoreFile.map(Format.home) ?? "No file chosen")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
                    Button("Choose…", action: actions.chooseRestoreFile)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Passphrase").font(.system(size: 12, weight: .semibold))
                SecureField("The passphrase the file was saved with", text: $model.restorePassphrase)
                    .textFieldStyle(.roundedBorder)
            }
            if let error = model.restoreError {
                Text(error).font(.system(size: 12)).foregroundStyle(Color(StatusMark.amber)).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No passphrase, no recovery: nobody can reset it, including us.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .disabled(model.restoreBusy)
    }

    private var explanation: String {
        if model.strandedSecrets > 0 {
            let n = model.strandedSecrets == 1 ? "1 secret is" : "\(model.strandedSecrets) secrets are"
            return "\(n) stored here, but the key that opens them is not in this Mac’s keychain. That happens when files are "
                + "restored from a backup or moved to a new Mac. A recovery file brings them back."
        }
        return "A recovery file saved on your other Mac, and its passphrase, put every secret into a new vault here. "
            + "Your files on this Mac are not touched."
    }
}

struct OnboardingHeadline: View {
    let number: String
    let label: String
    let trailing: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number).font(.system(size: 44, weight: .bold)).foregroundStyle(tint)
            Text(label).font(.system(size: 17, weight: .semibold))
            Spacer()
            Text(trailing).foregroundStyle(.secondary)
        }
    }
}

struct OnboardingBar: View {
    let percent: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14))
                Capsule().fill(Color(StatusMark.green)).frame(width: proxy.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("\(percent) percent protected")
    }
}
