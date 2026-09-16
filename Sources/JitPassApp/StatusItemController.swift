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
    private let client: AgentClient
    private let item: NSStatusItem
    private let model = MenuModel()
    private lazy var panel = MenuPanel(content: PanelView(model: model, actions: panelActions))
    private lazy var auditWindow = ReportWindow(
        title: "JitPass Audit",
        content: AuditView(model: model, actions: auditActions),
        size: NSSize(width: 720, height: 480),
        minSize: NSSize(width: 520, height: 320)
    )
    private lazy var scanWindow = ReportWindow(
        title: "JitPass Scan",
        content: ScanReportView(model: model, actions: scanActions),
        size: NSSize(width: 640, height: 520),
        minSize: NSSize(width: 480, height: 320)
    )
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
            revoke: { [weak self] id in self?.revokeGrant(id) },
            runScan: { [weak self] in self?.openScan() },
            openScan: { [weak self] in self?.openScan() },
            openAudit: { [weak self] in self?.openAudit() },
            quit: { NSApp.terminate(nil) }
        )
    }

    private var scanActions: ScanActions {
        ScanActions(
            rescan: { [weak self] in self?.runScan() },
            chooseFolder: { [weak self] in self?.chooseScanFolder() },
            scanWholeMac: { [weak self] in
                self?.model.scanScope = nil
                self?.runScan()
            },
            openInTerminal: { [weak self] in self?.openScanInTerminal() },
            fix: { [weak self] command in self?.runInTerminal(command) }
        )
    }

    private var auditActions: AuditActions {
        AuditActions(
            setFilter: { [weak self] filter in
                guard let self, filter != model.auditFilter else {
                    return
                }
                model.auditFilter = filter
                reloadAudit()
            },
            openInTerminal: { [weak self] in self?.runInTerminal("jit audit") }
        )
    }

    // MARK: - Audit

    private func openAudit() {
        panel.dismiss()
        auditWindow.present()
        reloadAudit()
    }

    /// Re-reads `jit audit` with the current filter, off the main thread.
    /// Called on open, on every filter change, and on every stream event
    /// while the window is showing, so the tail is never behind the CLI.
    private func reloadAudit() {
        guard !model.auditLoading else {
            return
        }
        model.auditLoading = true
        let filter = model.auditFilter
        Task.detached {
            let report = JitCLI.audit(filter)
            await MainActor.run { [weak self] in
                self?.model.audit = report
                self?.model.auditLoading = false
            }
        }
    }

    // MARK: - Scan

    /// Opens the report. Nothing is scanned until the user chooses a scope
    /// in the window; a whole-home read is never a side effect of a click.
    private func openScan() {
        panel.dismiss()
        scanWindow.present()
    }

    /// The standard folder picker; a choice limits the next scan to it,
    /// exactly as `jit scan <path>` would.
    private func chooseScanFolder() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.prompt = "Scan"
        picker.message = "Choose a folder to scan for plaintext secrets."
        picker.directoryURL = model.scanScope.map { URL(fileURLWithPath: $0) }
        guard picker.runModal() == .OK, let url = picker.url else {
            return
        }
        model.scanScope = url.path
        runScan()
    }

    private func openScanInTerminal() {
        let scope = model.scanScope.map { " " + Terminal.quoted($0) } ?? ""
        runInTerminal("jit scan --full" + scope)
    }

    /// Runs `jit scan` off the main thread and publishes the report. The
    /// scan is read-only and never prompts, which is what makes it safe to
    /// start from a click.
    private func runScan() {
        guard !model.scanning else {
            return
        }
        model.scanning = true
        model.scanError = nil
        let scope = model.scanScope
        Task.detached {
            let result = Result { try JitCLI.scan(path: scope) }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.scanning = false
                switch result {
                case let .success(report): model.scan = report
                case let .failure(error): model.scanError = "scan failed: \(error)"
                }
            }
        }
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
            render()
            return
        }
        model.grants = []
        render()
    }

    private func pollStatus() {
        do {
            let status = try client.status()
            model.state = SessionState(response: status)
            model.consentEnabled = status.consentEnabled
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

    private func revokeGrant(_ id: String) {
        try? client.revokeGrant(id: id)
        model.grants = (try? client.grants()) ?? []
    }

    private func runInTerminal(_ command: String) {
        panel.dismiss()
        Terminal.run(command)
    }
}
