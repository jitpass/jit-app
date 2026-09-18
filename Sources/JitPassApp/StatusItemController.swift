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
    let item: NSStatusItem
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
    lazy var vaultWindow = ReportWindow(
        title: "JitPass Vault",
        content: VaultView(model: model, actions: vaultActions),
        size: NSSize(width: 860, height: 540),
        minSize: NSSize(width: 720, height: 400)
    )
    lazy var agentsWindow = ReportWindow(
        title: "JitPass AI Agents",
        content: AgentsView(model: model, actions: agentsActions),
        size: NSSize(width: 720, height: 600),
        minSize: NSSize(width: 600, height: 400)
    )
    lazy var toolsWindow = ReportWindow(
        title: "JitPass Tools",
        content: ToolsView(model: model, actions: toolsActions),
        size: NSSize(width: 760, height: 480),
        minSize: NSSize(width: 640, height: 360)
    )
    /// The one revealed value's bytes; wiped by `hideReveal()`.
    var revealBuffer: SecretBuffer?
    var revealTimer: Timer?
    var vaultObservers: [NSObjectProtocol] = []
    /// When the tool listing was last read, for the panel rows.
    var toolsReadAt: Date?
    lazy var settingsWindow = ReportWindow(
        title: "JitPass Settings",
        content: SettingsView(model: model, actions: settingsActions),
        size: NSSize(width: 480, height: 360),
        minSize: NSSize(width: 480, height: 360)
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
    let onboarding = OnboardingModel()
    var onboardingScanRun: JitCLI.ScanRun?
    var onboardingAccessPoll: Timer?
    lazy var onboardingWindow = makeOnboardingWindow()
    let offboarding = OffboardingModel()
    lazy var offboardingWindow = makeOffboardingWindow()

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
    private var scanCheck: Timer?
    var updateCheck: Timer?
    /// The minute timer behind the session notifications.
    var sessionCheck: Timer?
    /// "profile:expiry:stage" for every session notice already posted, so
    /// each session is announced once per stage, never per tick.
    var sessionNotices: Set<String> = []
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
        LoginShell.warm()
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        installNotifications()
        refreshDecoyReads()
        resync()
        openStream()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollStatus() }
        }
        model.fullDiskAccess = FullDiskAccess.granted()
        refreshScanIfDue()
        scanCheck = Timer.scheduledTimer(withTimeInterval: Self.scanCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshScanIfDue() }
        }
        startUpdateChecks()
        openOnboardingOnFirstLaunch()
        offerCommandLineToolAfterLaunch()
    }

    private var panelActions: PanelActions {
        PanelActions(
            lock: { [weak self] in self?.lockNow() },
            unlock: { [weak self] in self?.unlockNow() },
            openGrants: { [weak self] in self?.openGrants() },
            openVault: { [weak self] in self?.openVault() },
            openTools: { [weak self] in self?.openTools() },
            openAgents: { [weak self] in self?.openAgents() },
            newGrant: { [weak self] in self?.openGrantSheet() },
            runScan: { [weak self] in self?.openScan() },
            openScan: { [weak self] in self?.openScan() },
            openDoctor: { [weak self] in self?.openDoctor() },
            openAudit: { [weak self] in self?.openAudit() },
            openDecoys: { [weak self] in self?.openAudit(filter: AuditFilter(kinds: ["serve"], since: "7d")) },
            openSettings: { [weak self] in self?.openSettings() },
            openConsent: { [weak self] in self?.openConsent() },
            about: { [weak self] in self?.showAbout() },
            installUpdate: { [weak self] in self?.installUpdate() },
            continueSetup: { [weak self] in self?.continueSetup() },
            setUpInTerminal: { [weak self] in self?.setUpInTerminal() },
            quit: { NSApp.terminate(nil) }
        )
    }

    // MARK: - Feeds

    /// One full read of everything the panel shows. Runs at start, on every
    /// stream (re)connect, and on every open, because whatever was recorded
    /// while no stream was open is only in `history`, and the CLI report is
    /// only ever as fresh as its last run.
    func resync() {
        pollStatus()
        model.cli = JitCLI.status()
        reloadToolsIfStale()
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
        if event.isDecoyServe {
            model.decoyReads24h = (model.decoyReads24h ?? 0) + (event.count ?? 1)
            if model.notifyDecoys {
                let who = event.by.map { String($0.split(separator: "/").last ?? Substring($0)) } ?? "an unknown reader"
                let launcher = event.launchedBy.map { ", launched by \($0)" } ?? ""
                let file = event.labels?.first ?? "a protected file"
                Notifier.post(
                    title: "Decoy served to \(who)",
                    body: "It read \(file)\(launcher) with no grant covering it, and got fake values.",
                    id: "decoy-\(event.unixTime)-\(event.byPID ?? 0)"
                )
            }
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

    /// The menu bar item itself: mark colour and tooltip. Re-run on every
    /// state change and whenever a consent request arrives or resolves.
    func render() {
        let asking = model.consentRequests.first
        item.button?.image = StatusMark.image(for: model.state, asking: asking != nil, needsSetup: model.showsSetup)
        item.button?.imagePosition = .imageOnly
        item.button?.title = ""
        item.button?.toolTip = StatusMark.tooltip(
            for: model.state, asking: asking, needsSetup: model.needsSetup, needsRestore: model.needsRestore
        )
    }

    @objc private func togglePanel() {
        guard let button = item.button else {
            return
        }
        if !panel.isVisible {
            hideReveal(reason: "panel opened")
            resync()
            refreshDecoyReads()
            refreshDoctorIfStale()
            refreshScanIfDue()
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
        guard case .notRunning = model.state else {
            _ = try? client.unlock()
            pollStatus()
            return
        }
        startService()
    }

    func runInTerminal(_ command: String) {
        panel.dismiss()
        Terminal.run(command)
    }
}
