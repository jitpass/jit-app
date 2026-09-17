// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The two notifications the panel's dots already imply: a captured
/// session running out, and a scan finding cached copies it had not seen.
/// Both are off with one switch in Settings; both are said once.
extension StatusItemController {
    /// How often the sessions are re-read for the expiry notices. `jit
    /// status` is prompt-free and cheap; a minute keeps "expires in 10
    /// minutes" honest.
    static let sessionCheckInterval: TimeInterval = 60

    /// Below this, a live session is announced as about to expire.
    static let sessionWarning: Int64 = 15 * 60

    /// Delegate, click routing, the permission prompt when either switch
    /// is on, and the minute timer.
    func installNotifications() {
        Notifier.install()
        Notifier.onActivate = { [weak self] target in
            switch target {
            case .audit: self?.openAudit(filter: AuditFilter(kinds: ["serve"], since: "7d"))
            case .agents: self?.openAgents()
            case .tools: self?.openTools()
            }
        }
        if Notifier.decoysEnabled || Notifier.changesEnabled {
            Notifier.requestPermission()
        }
        startSessionCheck()
    }

    /// `jit audit --kind serve --since 24h`, prompt-free, off the main
    /// thread: the Mounts row's count. The stream keeps it current between
    /// reads.
    func refreshDecoyReads() {
        Task.detached {
            let report = JitCLI.audit(AuditFilter(kinds: ["serve"], since: "24h", limit: 0))
            await MainActor.run { [weak self] in
                guard let report else {
                    return
                }
                self?.model.decoyReads24h = report.authEvents.filter(\.isDecoyServe).reduce(0) { $0 + ($1.count ?? 1) }
            }
        }
    }

    func startSessionCheck() {
        sessionCheck = Timer.scheduledTimer(withTimeInterval: Self.sessionCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSessions() }
        }
        checkSessions()
    }

    /// Re-reads status off the main thread and posts what changed. The
    /// cache is dropped first: a session that expired a minute ago must
    /// not read as live for another thirty seconds.
    func checkSessions() {
        guard model.notifyChanges else {
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
                for session in status.sessions ?? [] {
                    noteSession(session)
                }
            }
        }
    }

    /// One notice when a session comes within `sessionWarning` of its
    /// expiry, one when it has expired; a renewed session has a new expiry
    /// and so a new key.
    func noteSession(_ session: CLISession) {
        guard let expires = session.expiresUnix, expires > 0 else {
            return
        }
        let renew = session.mint.map { " Renew: \($0)." } ?? ""
        let base = "\(session.profile):\(expires)"
        if !session.live {
            guard sessionNotices.insert(base + ":expired").inserted else {
                return
            }
            Notifier.post(
                title: "\(session.profile) session expired",
                body: "The captured credentials are past their expiry; the next use fails until you renew.\(renew)",
                id: "session-expired-" + base, target: .tools
            )
        } else if let left = session.remainingSeconds, left <= Self.sessionWarning {
            guard sessionNotices.insert(base + ":soon").inserted else {
                return
            }
            let minutes = max(1, Int(left / 60))
            let at = Format.stamp(Date(timeIntervalSince1970: TimeInterval(expires)), withDay: false)
            Notifier.post(
                title: "\(session.profile) session expires in \(minutes) min",
                body: "The captured credentials run out at \(at).\(renew)",
                id: "session-soon-" + base, target: .tools
            )
        }
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
            id: "caches-\(Int(Date().timeIntervalSince1970))", target: .agents
        )
    }
}
