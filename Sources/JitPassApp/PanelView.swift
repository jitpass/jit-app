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
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

            VStack(spacing: 0) {
                if let vault = model.vaultValue {
                    row("archivebox", "Vault", vault)
                }
                row("play.circle", "Service", model.serviceValue)
                row("key", "Grants", model.grantsValue)
                ForEach(model.grants) { grant in
                    grantRow(grant)
                }
                if let mounts = model.mountsValue {
                    row("doc.text", "Mounts", mounts)
                }
                if let consent = model.consentValue {
                    row("hand.raised", "Consent", consent)
                }
            }

            if let event = model.lastEvent {
                Text("Last event: " + Format.event(event))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
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
            action("Run Scan", key: "r", actions.runScan)
            action("Open Audit", key: "a", actions.openAudit)
            divider
            action("Quit JitPass", key: "q", actions.quit)
                .padding(.bottom, 8)
        }
        .frame(width: 400)
        .foregroundStyle(Palette.primary)
        .background(Palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.edge, lineWidth: 0.5))
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 14) {
            StatusMarkView(state: model.state, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.state.headline).font(.system(size: 18, weight: .bold))
                Text(model.state.detail).font(.system(size: 14)).foregroundStyle(Palette.secondary)
            }
        }
    }

    private func row(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15)).frame(width: 20)
            Text(label)
            Spacer()
            Text(value)
        }
        .font(.system(size: 15))
        .frame(height: 34)
        .padding(.horizontal, 20)
    }

    private func grantRow(_ grant: GrantStatus) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 20)
            Text(Format.grant(grant)).foregroundStyle(Palette.secondary).lineLimit(1)
            Spacer()
            Button("Revoke") { actions.revoke(grant.id) }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
        }
        .font(.system(size: 13))
        .frame(height: 26)
        .padding(.horizontal, 20)
    }

    private var divider: some View {
        Rectangle().fill(Palette.edge).frame(height: 1)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }

    private func action(_ title: String, key: Character, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack {
                Text(title)
                Spacer()
                Text("⌘ " + String(key).uppercased()).foregroundStyle(Palette.tertiary).font(.system(size: 14))
            }
            .font(.system(size: 15))
            .frame(height: 30)
            .padding(.horizontal, 20)
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
    var revoke: (String) -> Void = { _ in }
    var runScan: () -> Void = {}
    var openAudit: () -> Void = {}
    var quit: () -> Void = {}
}

/// The mockup's inks. Panel and edge are the dark translucent surface; the
/// state colours live in StatusMark so the menu bar icon and the panel
/// header can never disagree.
enum Palette {
    static let panel = Color(red: 52 / 255, green: 48 / 255, blue: 88 / 255).opacity(0.94)
    static let edge = Color.white.opacity(0.14)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.6)
    static let tertiary = Color.white.opacity(0.45)
    static let accent = Color(StatusMark.accent)
}

private struct HoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.1) : .clear)
    }
}

/// The jitpass mark as a SwiftUI view, same geometry as the NSImage the
/// status item draws.
struct StatusMarkView: View {
    let state: SessionState
    let size: CGFloat

    var body: some View {
        let tint = Color(StatusMark.color(for: state))
        ZStack {
            Circle().fill(tint.opacity(0.22))
            Circle().fill(tint).padding(size * 0.22)
            if case .locked = state {
                Image(systemName: "lock.fill").font(.system(size: size * 0.28, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}
