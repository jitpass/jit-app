// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The notifications: a decoy served (the Decoys switch), and the two the
/// panel's dots already imply, a captured session running out and a scan
/// finding cached copies it had not seen (the second switch). Each is
/// said once.
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
            }
        }
        // Before setup has asked, the switches read as on by default; the
        // question itself waits for setup's finish screen (or Settings).
        if Notifier.chosen, Notifier.decoysEnabled || Notifier.changesEnabled {
            Notifier.requestPermission()
        }
        startSessionCheck()
    }

    /// `jit audit --kind serve --since 24h`, prompt-free, off the main
    /// thread: the Mounts row's count, with the live notices whose record
    /// has not landed yet. The stream keeps it current between reads.
    func refreshDecoyReads() {
        let filter = AuditFilter(kinds: ["serve"], since: "24h", limit: 0)
        Task.detached {
            let report = JitCLI.audit(filter)
            await MainActor.run { [weak self] in
                guard let self, let report else {
                    return
                }
                model.decoyReads24h = report.addingLive(liveServes, filter: filter).authEvents
                    .filter(\.readDecoy).reduce(0) { $0 + ($1.count ?? 1) }
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

    /// After a whole-Mac scan: the cached copies the previous scan of this
    /// run did not have. The first scan says nothing, because the AI
    /// Agents dot already carries it and a notice on every launch would be
    /// the same news each morning.
    func noteNewCachedCopies(in report: ScanReport, since previous: ScanReport?) {
        guard model.notifyChanges, let previous else {
            return
        }
        let fresh = report.newAgentCopies(since: previous)
        guard !fresh.isEmpty else {
            return
        }
        let agents = Array(Set(fresh.compactMap(\.agent))).sorted()
        let who = agents.isEmpty ? "an AI agent" : agents.joined(separator: ", ")
        let count = fresh.count
        Notifier.post(
            title: "\(count) new cached cop\(count == 1 ? "y" : "ies") of your secrets",
            body: "\(who) kept \(count == 1 ? "a copy" : "copies") of a protected value in its cache. Clean Caches redacts them.",
            id: "caches-\(Int(Date().timeIntervalSince1970))", thread: "caches", target: .agents
        )
    }
}
