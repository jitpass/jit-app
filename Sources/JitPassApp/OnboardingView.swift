// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The setup window, drawn to docs/design/mockups/onboarding: one fixed
/// frame, one decision per screen, the primary button bottom right.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let actions: OnboardingActions

    static let size = CGSize(width: 620, height: 540)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch model.step {
                case .welcome: OnboardingWelcome(actions: actions)
                case .fullDiskAccess: OnboardingAccess()
                case .scanning: OnboardingScanning(model: model)
                case .results: OnboardingResults(model: model, actions: actions)
                case .protecting: OnboardingProtecting(model: model)
                case .done: OnboardingDone(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 36)
            .padding(.top, 26)

            OnboardingFooter(model: model, actions: actions)
                .frame(height: 58)
                .padding(.horizontal, 36)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(VisualEffectBackground(material: .hudWindow, cornerRadius: 0))
    }
}

/// Step dots on the left, the screen's buttons on the right.
private struct OnboardingFooter: View {
    @ObservedObject var model: OnboardingModel
    let actions: OnboardingActions

    private var dotIndex: Int {
        switch model.step {
        case .welcome, .fullDiskAccess: 0
        case .scanning, .results: 1
        case .protecting: 2
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

    @ViewBuilder private var buttons: some View {
        switch model.step {
        case .welcome:
            EmptyView()
        case .fullDiskAccess:
            Button("Use Quick Scan Instead", action: actions.quickScan)
            Button("Open System Settings", action: actions.openFullDiskAccess).keyboardShortcut(.defaultAction)
        case .scanning:
            Button("Cancel", action: actions.cancelScan).keyboardShortcut(.cancelAction)
        case .results:
            resultsButtons
        case .protecting:
            if model.failedTask != nil {
                Button("Close", action: actions.notNow)
                Button("Try Again", action: actions.retry).keyboardShortcut(.defaultAction)
            } else {
                Text("This window stays open until it is safe to close.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .done:
            if (model.report?.summary.secretsManual ?? 0) > 0 {
                Button("See What Needs You", action: actions.openScanReport)
            }
            Button("Done", action: actions.done).keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private var resultsButtons: some View {
        if model.scanError != nil {
            Button("Back", action: actions.back)
        } else if model.tasks.isEmpty {
            Button("Scan Again", action: actions.back)
            Button("Done", action: actions.done).keyboardShortcut(.defaultAction)
        } else {
            Button("Not Now", action: actions.notNow)
            Button(protectTitle, action: actions.protect).keyboardShortcut(.defaultAction)
        }
    }

    private var protectTitle: String {
        let n = model.report?.summary.secretsMigratable ?? 0
        if n == 0 {
            return "Create My Vault"
        }
        return n == 1 ? "Protect 1 Secret" : "Protect \(n) Secrets"
    }
}

// MARK: - Welcome

private struct OnboardingWelcome: View {
    let actions: OnboardingActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                StatusMarkView(state: .unlocked(expiresIn: 0, ceilingAt: nil), size: 40)
                Text("Welcome to JitPass").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            Text("Your secrets are sitting in plain files.").font(.system(size: 24, weight: .bold))
            Text(
                "API keys in .env, tokens in .npmrc, cloud credentials in ~/.aws. Anything running as you can read them. "
                    + "JitPass moves them into a vault that opens with your fingerprint, and your tools keep working."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Text("First, a look. It only reads, and nothing leaves this Mac.").fontWeight(.semibold).padding(.top, 4)
            HStack(alignment: .top, spacing: 14) {
                ScanChoiceCard(
                    title: "Quick scan", first: "About 5 seconds, no permissions.",
                    second: "Skips Desktop, Documents and Downloads.",
                    button: "Quick Scan", isDefault: true, action: actions.quickScan
                )
                ScanChoiceCard(
                    title: "Full scan", first: "Every folder, the complete number.",
                    second: "Needs Full Disk Access: one switch in System Settings.",
                    button: "Full Scan…", isDefault: false, action: actions.fullScan
                )
            }
            HStack {
                Spacer()
                Button("or choose a folder…", action: actions.chooseFolder).buttonStyle(.link).font(.system(size: 12))
                Spacer()
            }
        }
        .font(.system(size: 13))
    }
}

/// One scan choice. Both cards carry the same prominent button: the user
/// chooses, and neither is dressed as the recommended one. Return presses
/// Quick Scan only because it is the one that needs nothing.
private struct ScanChoiceCard: View {
    let title: String
    let first: String
    let second: String
    let button: String
    let isDefault: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 15, weight: .bold))
            Text(first).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(second).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if isDefault {
                Button(button, action: action).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                Button(button, action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
    }
}

// MARK: - Full Disk Access

private struct OnboardingAccess: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A full scan needs Full Disk Access").font(.system(size: 22, weight: .bold))
            Text(
                "macOS keeps Desktop, Documents and Downloads closed to every app until you open them. Without this switch "
                    + "it would ask you folder by folder. JitPass only reads, and only on this Mac."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                numbered(1, "Open System Settings. It lands on the right page.")
                numbered(2, "Turn on JitPass in the list.")
                numbered(3, "Come back. The scan starts by itself.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Waiting for the switch…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text("macOS may ask to quit and reopen JitPass. Setup is in the menu bar when you come back.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
    }

    private func numbered(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(.system(size: 11, weight: .bold)).frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(0.14)))
            Text(text)
        }
    }
}

// MARK: - Scanning

private struct OnboardingScanning: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Looking…").font(.system(size: 22, weight: .bold))
            Text("Reading only. Nothing is changed, and nothing leaves this Mac.").foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(model.scanLines == 0 ? "Walking your files" : "\(model.scanLines) found so far")
                    .font(.system(size: 13).monospacedDigit())
            }
            .padding(.top, 8)
        }
        .font(.system(size: 13))
    }
}
