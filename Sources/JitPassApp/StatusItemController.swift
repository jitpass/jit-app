// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Owns the NSStatusItem and rebuilds its menu from the agent's answers.
/// Every menu action is one socket op the CLI can also send; nothing here
/// decides anything on its own.
@MainActor
final class StatusItemController {
    private let client: AgentClient
    private let item: NSStatusItem
    private var refreshTimer: Timer?
    private var state: SessionState = .notRunning
    private var grants: [GrantStatus] = []
    private var lastEvent: SessionEvent?

    init(client: AgentClient) {
        self.client = client
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    func start() {
        refresh()
        // A 1 s tick keeps the countdown honest; the subscribe op in the
        // design doc replaces this with push once the agent grows it.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Data

    private func refresh() {
        do {
            let status = try client.status()
            state = SessionState(response: status)
            grants = (try? client.grants()) ?? []
            lastEvent = (try? client.history())?.last
        } catch AgentClientError.notRunning {
            state = .notRunning
            grants = []
        } catch {
            // Keep the last known state on a transient error; the next tick retries.
        }
        render()
    }

    // MARK: - Rendering

    private func render() {
        item.button?.image = StatusMark.image(for: state)
        item.button?.imagePosition = .imageLeading
        item.button?.title = " " + StatusMark.pillTitle(for: state)
        item.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(header(state.headline, detail: state.detail))
        menu.addItem(.separator())

        menu.addItem(row("Grants", value: grantsSummary))
        for grant in grants {
            menu.addItem(grantRow(grant))
        }
        if let event = lastEvent {
            menu.addItem(disabled("Last event: \(Format.event(event))"))
        }
        menu.addItem(.separator())

        switch state {
        case .unlocked:
            menu.addItem(action("Lock Now", key: "l", #selector(lockNow)))
        case .locked:
            menu.addItem(action("Unlock with Touch ID", key: "u", #selector(unlockNow)))
        case .notRunning:
            menu.addItem(action("Start Service", key: "u", #selector(unlockNow)))
        }
        menu.addItem(action("Run Scan", key: "r", #selector(runScan)))
        menu.addItem(action("Open Audit", key: "a", #selector(openAudit)))
        menu.addItem(.separator())
        menu.addItem(action("Quit JitPass", key: "q", #selector(NSApplication.terminate(_:)), target: NSApp))
        return menu
    }

    private var grantsSummary: String {
        switch grants.count {
        case 0: "none"
        case 1: "1 active"
        default: "\(grants.count) active"
        }
    }

    private func grantRow(_ grant: GrantStatus) -> NSMenuItem {
        let row = NSMenuItem(title: Format.grant(grant), action: #selector(revokeGrant(_:)), keyEquivalent: "")
        row.target = self
        row.representedObject = grant.id
        row.toolTip = "Click to revoke. Revoking needs no authentication."
        return row
    }

    // MARK: - Actions (each is exactly one CLI-equivalent op)

    @objc private func lockNow() {
        _ = try? client.lock(); refresh()
    }

    @objc private func unlockNow() {
        _ = try? client.unlock(); refresh()
    }

    @objc private func revokeGrant(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        try? client.revokeGrant(id: id)
        refresh()
    }

    @objc private func runScan() {
        Terminal.run("jit scan")
    }

    @objc private func openAudit() {
        Terminal.run("jit audit")
    }

    // MARK: - Menu item helpers

    private func header(_ title: String, detail: String) -> NSMenuItem {
        let text = NSMutableAttributedString(string: title + "\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 15)])
        text.append(NSAttributedString(
            string: detail,
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        ))
        let row = NSMenuItem()
        row.attributedTitle = text
        row.isEnabled = false
        return row
    }

    private func row(_ label: String, value: String) -> NSMenuItem {
        disabled("\(label)\t\(value)")
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        row.isEnabled = false
        return row
    }

    private func action(_ title: String, key: String, _ selector: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        row.target = target ?? self
        return row
    }
}
