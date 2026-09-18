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
                Text("Link values that already live in 1Password · 1Password will ask to authorise").font(.system(size: 12))
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

private struct OnboardingTaskRow: View {
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

    var body: some View {
        let s = model.report?.summary
        VStack(alignment: .leading, spacing: 14) {
            OnboardingHeadline(
                number: "\(s?.percent ?? 0)%", label: "protected",
                trailing: "\(s?.secretsProtected ?? 0) of \(s?.secretsTotal ?? 0) secrets in the vault", tint: Color(StatusMark.green)
            )
            OnboardingBar(percent: s?.percent ?? 0)
            Text(
                "Your tools work as before. macOS asks for Touch ID about once per 5 minutes of use. "
                    + "Open a new terminal window to pick up the change."
            )
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let manual = s?.secretsManual, manual > 0 {
                Text("\(manual) \(manual == 1 ? "secret needs" : "secrets need") you: rotate or remove. The scan report shows each one.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Every rewritten file has an encrypted backup in the vault.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("JitPass lives in the menu bar. Click the ring any time.").fontWeight(.semibold).padding(.top, 4)
        }
        .font(.system(size: 13))
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
