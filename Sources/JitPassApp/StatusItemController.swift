// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Owns the NSStatusItem and rebuilds its menu from the agent's answers.
/// Every menu action is one socket op the CLI can also send; nothing here
/// decides anything on its own.
///
/// Two feeds drive it. A `subscribe` stream delivers every session event
/// as the agent records it, which is when grants and the event tail change.
/// A one-second `status` poll keeps the countdown honest; it is the one
/// thing a stream cannot carry, since nothing is recorded as time passes.
@MainActor
final class StatusItemController {
    private let client: AgentClient
    private let item: NSStatusItem
    private var tick: Timer?
    private var stream: Subscription?
    private var reconnect: Timer?

    private var state: SessionState = .notRunning
    private var grants: [GrantStatus] = []
    private var lastEvent: SessionEvent?

    /// How long to wait before re-opening a stream that ended. Long enough
    /// not to hammer a restarting agent, short enough that the tail is never
    /// visibly behind the CLI.
    private let reconnectDelay: TimeInterval = 2

    init(client: AgentClient) {
        self.client = client
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    func start() {
        resync()
        openStream()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollStatus() }
        }
    }

    // MARK: - Feeds

    /// One full read of everything the menu shows. Runs at start and on
    /// every stream (re)connect, because whatever was recorded while no
    /// stream was open is only in `history`.
    private func resync() {
        pollStatus()
        guard case .notRunning = state else {
            grants = (try? client.grants()) ?? []
            lastEvent = (try? client.history())?.first
            render()
            return
        }
        grants = []
        render()
    }

    private func pollStatus() {
        do {
            state = try SessionState(response: client.status())
        } catch AgentClientError.notRunning {
            state = .notRunning
            grants = []
        } catch {
            // Keep the last known state on a transient error; the next tick retries.
        }
        render()
    }

    private func openStream() {
        stream?.cancel()
        stream = client.subscribe(
            onEvent: { [weak self] event in
                Task { @MainActor in self?.apply(event) }
            },
            onEnd: { [weak self] _ in
                Task { @MainActor in self?.scheduleReconnect() }
            }
        )
    }

    /// A recorded event is the only time the grants list or the tail can
    /// change, so this is where they are re-read. Grants are re-listed rather
    /// than patched: the agent is the record, and one round trip is cheap.
    private func apply(_ event: SessionEvent) {
        lastEvent = event
        grants = (try? client.grants()) ?? []
        pollStatus()
    }

    private func scheduleReconnect() {
        reconnect?.invalidate()
        reconnect = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resync()
                self?.openStream()
            }
        }
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
        _ = try? client.lock()
        pollStatus()
    }

    @objc private func unlockNow() {
        _ = try? client.unlock()
        pollStatus()
    }

    @objc private func revokeGrant(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        try? client.revokeGrant(id: id)
        grants = (try? client.grants()) ?? []
        render()
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
