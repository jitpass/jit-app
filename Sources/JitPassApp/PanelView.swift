// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The dropdown, drawn to docs/design/mockups/Main.dc.html: mark and headline,
/// state rows with an icon, the last event, then actions with shortcuts.
/// Every action closure is one socket op or one terminal command, wired by
/// the controller.
struct PanelView: View {
    @ObservedObject var model: MenuModel
    let actions: PanelActions

    var body: some View {
        if model.showsSetup {
            setupBody
        } else {
            sessionBody
        }
    }

    /// The panel before setup (docs/design/mockups/onboarding/SetupPanel):
    /// one thing to do, and none of the rows that have nothing to show yet.
    private var setupBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                StatusMarkView(state: model.state, needsSetup: true, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.needsRestore ? "Vault cannot be opened" : "Not set up yet").font(.system(size: 15, weight: .bold))
                    Text(model.needsRestore ? "its key is not on this Mac" : "takes about two minutes")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Text(
                model.needsRestore
                    ? "Secrets are stored here, but nothing opens them. A recovery file and its passphrase bring them back."
                    : "JitPass finds the secrets in your plain files and locks them behind Touch ID."
            )
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Button(action: actions.continueSetup) {
                Text(model.needsRestore ? "Restore…" : "Continue Setup…").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            divider
            if !model.needsRestore {
                plainAction("I’ll Set Up in Terminal", actions.setUpInTerminal)
                divider
            }
            action("Settings…", key: ",", actions.openSettings)
            plainAction("About JitPass", actions.about)
            divider
            action("Quit JitPass", key: "q", actions.quit)
                .padding(.bottom, 5)
        }
        .frame(width: 300)
        .background(VisualEffectBackground(material: .menu, cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var sessionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                if let request = model.consentRequests.first {
                    Button(action: actions.openConsent) {
                        row("hand.raised", "Asking", "\(request.program) · answer", dot: Color(StatusMark.amber))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverRowStyle())
                }
                if let vault = model.vaultValue {
                    Button(action: actions.openVault) {
                        row("archivebox", "Vault", vault)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverRowStyle())
                }
                if let agents = model.agentsValue {
                    Button(action: actions.openAgents) {
                        row("sparkles", "AI Agents", agents, dot: dot(model.agentsState))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverRowStyle())
                }
                if let tools = model.toolsValue {
                    Button(action: actions.openTools) {
                        row("terminal", "Tools", tools, dot: dot(model.toolsState))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverRowStyle())
                }
                row("play.circle", "Service", model.serviceValue)
                Button(action: actions.openGrants) {
                    row("key", "Grants", model.grantsValue, dot: model.grants.isEmpty ? nil : Color(StatusMark.green))
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverRowStyle())
                if let mounts = model.mountsValue {
                    Button(action: actions.openDecoys) {
                        row("eye.slash", "Decoys", mounts, dot: (model.decoyReads24h ?? 0) > 0 ? Color(StatusMark.amber) : nil)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverRowStyle())
                }
                Button(action: actions.openDoctor) {
                    row("stethoscope", "Doctor", model.doctorValue, dot: doctorDot)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverRowStyle())
                Button(action: actions.openScan) {
                    row("scope", "Findings", model.findingsValue, dot: findingsDot)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverRowStyle())
                if let update = model.updateAvailable {
                    Button(action: actions.installUpdate) {
                        row("arrow.down.circle", "Update", "\(update) available", dot: Color(StatusMark.amber))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverRowStyle())
                }
            }

            divider
            switch model.state {
            case .unlocked:
                action("Lock Now", key: "l", actions.lock)
            case .locked:
                action("Unlock with Touch ID", key: "u", actions.unlock)
            case .notRunning:
                action("Start Service", key: "u", actions.unlock)
            }
            action("New Grant…", key: "g", actions.newGrant)
            action("New Scan…", key: "r", actions.runScan)
            action("Open Audit", key: "a", actions.openAudit)
            divider
            action("Settings…", key: ",", actions.openSettings)
            plainAction("About JitPass", actions.about)
            divider
            action("Quit JitPass", key: "q", actions.quit)
                .padding(.bottom, 5)
        }
        .frame(width: 300)
        .background(VisualEffectBackground(material: .menu, cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Pieces

    /// While a request waits, the header says so and the session state moves
    /// to the second line, so nothing is lost and the question comes first.
    private var header: some View {
        let asking = model.consentRequests.first
        return HStack(spacing: 10) {
            StatusMarkView(state: model.state, asking: asking != nil, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                if let asking {
                    Text("Asking").font(.system(size: 15, weight: .bold))
                    Text("\(asking.program) · \(model.state.headline.lowercased()) · \(model.state.detail)")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(model.state.headline).font(.system(size: 15, weight: .bold))
                    Text(model.state.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func dot(_ state: AgentsState?) -> Color? {
        switch state {
        case .green: Color(StatusMark.green)
        case .amber: Color(StatusMark.amber)
        case .red: Color(StatusMark.red)
        case nil: nil
        }
    }

    private var doctorDot: Color? {
        guard !model.doctorRunning, let doctor = model.doctor else {
            return nil
        }
        if !doctor.problems.isEmpty {
            return Color(StatusMark.red)
        }
        return doctor.warnings.isEmpty ? Color(StatusMark.green) : Color(StatusMark.amber)
    }

    /// The window's own colours: green when no card asks anything, red
    /// when one is a copy in the open or only the user can fix it, amber
    /// when one command closes the gap; none until known.
    private var findingsDot: Color? {
        guard let report = model.macScan else {
            return nil
        }
        let tiers = report.tiersPresent.filter { $0 != .testFixtures }
        guard let worst = tiers.max(by: { Self.urgency($0) < Self.urgency($1) }) else {
            return Color(StatusMark.green)
        }
        return Color(ScanReportView.tierTint(worst))
    }

    private static func urgency(_ tier: ScanTier) -> Int {
        tier == .protect ? 1 : 2
    }

    private func row(_ symbol: String, _ label: String, _ value: String, dot: Color? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 12)).imageScale(.medium).frame(width: 16, height: 16)
            Text(label)
            Spacer()
            if let dot {
                Circle().fill(dot).frame(width: 8, height: 8)
            }
            Text(value)
        }
        .font(.system(size: 13))
        .frame(height: 26)
        .padding(.horizontal, 14)
    }

    private var divider: some View {
        Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
    }

    private func plainAction(_ title: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack {
                Text(title)
                Spacer()
            }
            .font(.system(size: 13))
            .frame(height: 24)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
    }

    private func action(_ title: String, key: Character, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack {
                Text(title)
                Spacer()
                Text("⌘ " + String(key).uppercased()).foregroundStyle(.tertiary).font(.system(size: 12))
            }
            .font(.system(size: 13))
            .frame(height: 24)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
        .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
    }
}

/// What the panel can ask the controller to do. A struct of closures rather
/// than a protocol so previews and tests can hand in no-ops.
struct PanelActions {
    var lock: () -> Void = {}
    var unlock: () -> Void = {}
    var openGrants: () -> Void = {}
    var openVault: () -> Void = {}
    var openTools: () -> Void = {}
    var openAgents: () -> Void = {}
    var newGrant: () -> Void = {}
    var runScan: () -> Void = {}
    var openScan: () -> Void = {}
    var openDoctor: () -> Void = {}
    var openAudit: () -> Void = {}
    var openDecoys: () -> Void = {}
    var openSettings: () -> Void = {}
    var openConsent: () -> Void = {}
    var about: () -> Void = {}
    var installUpdate: () -> Void = {}
    var continueSetup: () -> Void = {}
    var setUpInTerminal: () -> Void = {}
    var quit: () -> Void = {}
}

/// Severity and risk-level colours, jit's own: red is a state the user
/// must act on, amber needs a look, green is fine.
enum Severity {
    static func color(_ level: String) -> Color {
        switch level {
        case "critical", "high": Color(StatusMark.red)
        case "medium", "low": Color(StatusMark.amber)
        default: Color(StatusMark.green)
        }
    }
}

/// A menu row's highlight: the accent colour under the pointer with white
/// text, inset and rounded the way macOS draws its own menu items.
private struct HoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(pressed: configuration.isPressed) { configuration.label }
    }
}

private struct HoverHighlight<Label: View>: View {
    var pressed: Bool
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        let lit = hovering || pressed
        label()
            .foregroundStyle(lit ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(lit ? Color.accentColor : .clear)
                    .padding(.horizontal, 5)
            )
            .onHover { hovering = $0 }
    }
}

/// The jitpass mark as a SwiftUI view, same geometry as the NSImage the
/// status item draws.
struct StatusMarkView: View {
    let state: SessionState
    var asking = false
    var needsSetup = false
    let size: CGFloat

    var body: some View {
        if needsSetup, !asking {
            ZStack {
                Circle().fill(Color(StatusMark.amber).opacity(0.16))
                Circle().strokeBorder(Color(StatusMark.amber), lineWidth: size * 0.085).padding(size * 0.25)
            }
            .frame(width: size, height: size)
        } else {
            filled
        }
    }

    private var filled: some View {
        let tint = Color(StatusMark.color(for: state, asking: asking))
        return ZStack {
            Circle().fill(tint.opacity(0.22))
            Circle().fill(tint).padding(size * 0.22)
            if asking {
                Image(systemName: "questionmark").font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(.white)
            } else if case .locked = state {
                Image(systemName: "lock.fill").font(.system(size: size * 0.28, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}
