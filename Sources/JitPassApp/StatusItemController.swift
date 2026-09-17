// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Owns the NSStatusItem, the panel under it, and the model the panel
/// renders. Every action is one socket op the CLI can also send; nothing
/// here decides anything on its own.
///
/// Two feeds drive it. A `subscribe` stream delivers every session event
/// as the agent records it, which is when grants and the event tail change.
/// A one-second `status` poll keeps the countdown honest; it is the one
/// thing a stream cannot carry, since nothing is recorded as time passes.
@MainActor
final class StatusItemController {
    let client: AgentClient
    private let item: NSStatusItem
    let model = MenuModel()
    lazy var panel = MenuPanel(content: PanelView(model: model, actions: panelActions))
    lazy var auditWindow = ReportWindow(
        title: "JitPass Audit",
        content: AuditView(model: model, actions: auditActions),
        size: NSSize(width: 720, height: 480),
        minSize: NSSize(width: 520, height: 320)
    )
    lazy var grantWindow = ReportWindow(
        title: "New Grant",
        content: GrantSheetView(model: model, actions: grantActions),
        size: NSSize(width: 520, height: 560),
        minSize: NSSize(width: 520, height: 480)
    )
    lazy var grantsWindow = ReportWindow(
        title: "JitPass Grants",
        content: GrantsView(model: model, actions: grantsActions),
        size: NSSize(width: 560, height: 320),
        minSize: NSSize(width: 480, height: 240)
    )
    lazy var settingsWindow = ReportWindow(
        title: "JitPass Settings",
        content: SettingsView(model: model, actions: settingsActions),
        size: NSSize(width: 460, height: 340),
        minSize: NSSize(width: 460, height: 300)
    )
    lazy var doctorWindow = ReportWindow(
        title: "JitPass Doctor",
        content: DoctorView(model: model, actions: doctorActions),
        size: NSSize(width: 640, height: 480),
        minSize: NSSize(width: 520, height: 320)
    )
    lazy var scanWindow = ReportWindow(
        title: "JitPass Scan",
        content: ScanReportView(model: model, actions: scanActions),
        size: NSSize(width: 640, height: 520),
        minSize: NSSize(width: 480, height: 320)
    )
    /// Floats above other windows: it appears in the middle of someone
    /// else's work, and the program that asked is waiting on the answer.
    lazy var consentWindow: ReportWindow = {
        let window = ReportWindow(
            title: "JitPass",
            content: ConsentView(model: model, actions: consentActions),
            size: NSSize(width: 500, height: 380),
            minSize: NSSize(width: 500, height: 300)
        )
        window.level = .floating
        return window
    }()

    private var tick: Timer?
    private var stream: Subscription?
    private var reconnect: Timer?

    /// How long to wait before re-opening a stream that ended. Long enough
    /// not to hammer a restarting agent, short enough that the tail is never
    /// visibly behind the CLI.
    private let reconnectDelay: TimeInterval = 2

    init(client: AgentClient) {
        self.client = client
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    func start() {
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        resync()
        openStream()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollStatus() }
        }
    }

    private var panelActions: PanelActions {
        PanelActions(
            lock: { [weak self] in self?.lockNow() },
            unlock: { [weak self] in self?.unlockNow() },
            openGrants: { [weak self] in self?.openGrants() },
            newGrant: { [weak self] in self?.openGrantSheet() },
            runScan: { [weak self] in self?.openScan() },
            openScan: { [weak self] in self?.openScan() },
            openDoctor: { [weak self] in self?.openDoctor() },
            openAudit: { [weak self] in self?.openAudit() },
            openSettings: { [weak self] in self?.openSettings() },
            openConsent: { [weak self] in self?.openConsent() },
            about: { [weak self] in self?.showAbout() },
            quit: { NSApp.terminate(nil) }
        )
    }

    // MARK: - Feeds

    /// One full read of everything the panel shows. Runs at start, on every
    /// stream (re)connect, and on every open, because whatever was recorded
    /// while no stream was open is only in `history`, and the CLI report is
    /// only ever as fresh as its last run.
    private func resync() {
        pollStatus()
        model.cli = JitCLI.status()
        guard case .notRunning = model.state else {
            model.grants = (try? client.grants()) ?? []
            model.lastEvent = (try? client.history())?.first
            syncConsentRequests()
            render()
            return
        }
        model.grants = []
        model.consentRequests = []
        render()
    }

    func pollStatus() {
        do {
            let status = try client.status()
            model.state = SessionState(response: status)
            model.consentEnabled = status.consentEnabled
            model.ttlSeconds = status.ttlSeconds
        } catch AgentClientError.notRunning {
            model.state = .notRunning
            model.grants = []
        } catch {
            // Keep the last known state on a transient error; the next tick retries.
        }
        render()
    }

    private func openStream() {
        stream?.cancel()
        stream = client.subscribe(
            broker: true,
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
        if event.kind == "pending" {
            receive(pending: event)
            return
        }
        if let consentID = event.consentID {
            resolve(consentID: consentID)
        }
        model.lastEvent = event
        model.grants = (try? client.grants()) ?? []
        pollStatus()
        if auditWindow.isVisible {
            reloadAudit()
        }
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
        item.button?.image = StatusMark.image(for: model.state)
        item.button?.imagePosition = .imageLeading
        item.button?.title = " " + StatusMark.pillTitle(for: model.state)
    }

    @objc private func togglePanel() {
        guard let button = item.button else {
            return
        }
        if !panel.isVisible {
            resync()
            refreshDoctorIfStale()
        }
        panel.toggle(under: button)
    }

    // MARK: - Actions (each is exactly one CLI-equivalent op)

    private func lockNow() {
        _ = try? client.lock()
        pollStatus()
    }

    private func unlockNow() {
        panel.dismiss()
        _ = try? client.unlock()
        pollStatus()
    }

    func revokeGrant(_ id: String) {
        try? client.revokeGrant(id: id)
        model.grants = (try? client.grants()) ?? []
    }

    func runInTerminal(_ command: String) {
        panel.dismiss()
        Terminal.run(command)
    }
}
