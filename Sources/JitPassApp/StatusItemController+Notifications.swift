// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The notifications: a decoy served (the Decoys switch), and the two the
/// panel's dots already imply, a captured session running out and a
/// scheduled scan finding something the previous one had not (the second
/// switch). Each is said once.
extension StatusItemController {
    /// How often the session notices are re-decided. Free: it reads the
    /// expiry stamps already held, and runs no `jit`.
    static let sessionCheckInterval: TimeInterval = 60

    /// How often the sessions themselves are re-read, to learn of new
    /// captures. Every `jit status` is a line in `jit audit`; once a minute
    /// was most of that log, and pushed the rest out of it within a day.
    static let sessionRefreshInterval: TimeInterval = 15 * 60

    /// How long a live decoy notice is kept for the audit and the Decoys
    /// count: the record lands when its hour-wide aggregate closes, plus
    /// the service's minute of flush slack.
    static let liveServeRetention: TimeInterval = 2 * 3600

    /// Delegate, click routing, the permission prompt once the user has
    /// chosen, and the minute timer.
    func installNotifications() {
        Notifier.install()
        Notifier.onActivate = { [weak self] target in
            switch target {
            case .audit: self?.openAudit(filter: AuditFilter(kinds: ["serve"], since: "7d"))
            case .agents: self?.openAgents()
            case .tools: self?.openTools()
            case .findings: self?.openScan()
            case .jobs: self?.openAIJobsForAttention()
            }
        }
        // Before setup has asked, the switches read as on by default; the
        // question itself waits for setup's finish screen (or Settings).
        if Notifier.chosen, Notifier.decoysEnabled || Notifier.changesEnabled {
            Notifier.requestPermission { [weak self] in self?.refreshNotificationPermission() }
        } else {
            refreshNotificationPermission()
        }
        // Coming back from System Settings activates the app: re-read then,
        // so the Settings row clears without a reopen.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNotificationPermission() }
        }
        startSessionCheck()
    }

    /// `-previewNotifications denied` (or `notAsked`) on the command line
    /// draws that Settings row on a Mac where notifications are allowed.
    func refreshNotificationPermission() {
        switch UserDefaults.standard.string(forKey: "previewNotifications") {
        case "denied":
            model.notificationPermission = .denied
            return
        case "notAsked":
            model.notificationPermission = .notAsked
            return
        default:
            break
        }
        Notifier.readPermission { [weak self] permission in
            self?.model.notificationPermission = permission
        }
    }

    /// Settings' "Allow Notifications": the switches as they stand become
    /// the user's choice, and macOS asks.
    func allowNotifications() {
        UserDefaults.standard.set(model.notifyDecoys, forKey: Notifier.decoyPreferenceKey)
        UserDefaults.standard.set(model.notifyChanges, forKey: Notifier.changesPreferenceKey)
        UserDefaults.standard.set(model.notifyJobs, forKey: Notifier.jobsPreferenceKey)
        Notifier.requestPermission { [weak self] in self?.refreshNotificationPermission() }
    }

    /// `jit audit --kind serve --since 24h`, prompt-free, off the main
    /// thread: the Mounts row's count, with the live notices whose record
    /// has not landed yet. The stream keeps it current between reads.
    func refreshDecoyReads() {
        // The week, not the day: the Decoys row and window read the same
        // events, and a file naming a missing secret is a week-old fact.
        let filter = AuditFilter(kinds: ["serve"], since: "7d", limit: 0)
        let dayAgo = Int64(Date().timeIntervalSince1970) - 86400
        Task.detached {
            let report = JitCLI.audit(filter)
            await MainActor.run { [weak self] in
                guard let self, let report else {
                    return
                }
                let week = report.addingLive(liveServes, filter: filter).authEvents.filter { $0.kind == "serve" }
                model.decoyEvents = week
                let reads = week.filter { $0.readDecoy && $0.unixTime >= dayAgo }
                model.decoyReads24h = reads.reduce(0) { $0 + ($1.count ?? 1) }
                // By reading program — the first word of `by`, its last
                // path segment — so the AI Agents digest can say "2 decoy
                // reads today" on claude's row and not on codex's.
                var byProgram: [String: Int] = [:]
                for event in reads {
                    guard let first = event.by?.split(separator: " ", maxSplits: 1).first, !first.isEmpty else {
                        continue
                    }
                    let program = String(first.split(separator: "/").last ?? first)
                    byProgram[program, default: 0] += event.count ?? 1
                }
                model.decoyReadsByProgram = byProgram
            }
        }
    }

    /// A `serve_start` from the stream: the first read of an aggregate
    /// whose record lands up to an hour from now. Kept for the audit and
    /// the count, and announced when a reader actually got decoys.
    func noteLiveServe(_ event: SessionEvent) {
        let cutoff = Date().timeIntervalSince1970 - Self.liveServeRetention
        liveServes.removeAll { TimeInterval($0.unixTime) < cutoff }
        liveServes.append(event)
        guard event.readDecoy else {
            return
        }
        model.decoyReads24h = (model.decoyReads24h ?? 0) + 1
        if model.notifyDecoys {
            let who = event.by.map { String($0.split(separator: "/").last ?? Substring($0)) } ?? "an unknown reader"
            let launcher = event.launchedBy.map { ", launched by \($0)" } ?? ""
            let file = event.labels?.first ?? "a protected file"
            Notifier.post(
                title: "Decoy served to \(who)",
                body: "It read \(file)\(launcher) with no grant covering it, and got fake values.",
                id: "decoy-\(event.unixTime)-\(event.byPID ?? 0)", thread: "decoys"
            )
        }
        if auditWindow.isVisible {
            reloadAudit()
        }
    }

    func startSessionCheck() {
        sessionCheck = Timer.scheduledTimer(withTimeInterval: Self.sessionCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSessions() }
        }
        checkSessions()
    }

    /// Decides from the expiry stamps already held, and re-reads status
    /// only when they are a quarter-hour old or a notice is due. The
    /// second is a confirmation: a session renewed since the last read
    /// has a new expiry, and must not be announced as running out.
    func checkSessions() {
        guard model.notifyChanges else {
            return
        }
        let fresh = sessionsReadAt.map { Date().timeIntervalSince($0) < Self.sessionRefreshInterval } ?? false
        if fresh, SessionNotices.due(model.cli?.sessions ?? [], now: Date(), told: Notifier.sessionsTold).isEmpty {
            return
        }
        Task.detached {
            JitCLI.forgetStatus()
            let status = JitCLI.status()
            await MainActor.run { [weak self] in
                guard let self, let status else {
                    return
                }
                model.cli = status
                sessionsReadAt = Date()
                postSessionNotices(status.sessions ?? [])
            }
        }
    }

    /// Posts what is due and remembers it across launches.
    func postSessionNotices(_ sessions: [CLISession]) {
        var told = SessionNotices.pruned(Notifier.sessionsTold, keeping: sessions)
        for notice in SessionNotices.due(sessions, now: Date(), told: told) {
            told.insert(notice.key)
            let renew = notice.mint.map { " Renew: \($0)." } ?? ""
            switch notice.stage {
            case .expired:
                Notifier.post(
                    title: "\(notice.profile) session expired",
                    body: "The captured credentials are past their expiry; the next use fails until you renew.\(renew)",
                    id: "session-" + notice.key, thread: "sessions", target: .tools
                )
            case .soon:
                let expires = Date(timeIntervalSince1970: TimeInterval(notice.expiresUnix))
                let minutes = max(1, Int(expires.timeIntervalSinceNow / 60))
                Notifier.post(
                    title: "\(notice.profile) session expires in \(minutes) min",
                    body: "The captured credentials run out at \(Format.stamp(expires, withDay: false)).\(renew)",
                    id: "session-" + notice.key, thread: "sessions", target: .tools
                )
            }
        }
        Notifier.sessionsTold = told
    }

    /// After a scheduled whole-Mac scan: what it found that the previous
    /// one did not, said once, naming it, and opening Findings when
    /// clicked. A run that changes nothing is silent. Only the schedule
    /// announces: a scan someone clicked is already on their screen, and
    /// the very first scan has nothing to compare with (`rememberFindings`
    /// leaves `macScanNew` nil).
    func announceNewFindings(_ fresh: [ScanFinding], at: Date) {
        guard model.notifyChanges, !fresh.isEmpty,
              let notice = ScanNotices.make(new: fresh, at: at, home: FileManager.default.homeDirectoryForCurrentUser.path)
        else {
            return
        }
        Notifier.post(
            title: notice.title, body: notice.body,
            id: "findings-\(Int(at.timeIntervalSince1970))", thread: "findings", target: .findings
        )
    }
}
