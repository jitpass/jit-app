// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One disclosed challenge the agent has parked with this app, read out of
/// its `pending` event into the facts the sheet shows. Every fact here is
/// the agent's own: the wording is the exact sentence the Touch ID would
/// carry, the command line and launcher are kernel-derived (or marked as a
/// scan), and nothing the requesting process claimed about itself is used.
public struct ConsentRequest: Sendable, Equatable, Identifiable {
    public let id: String
    public let event: SessionEvent

    public init?(event: SessionEvent) {
        guard event.kind == "pending", let id = event.consentID, !id.isEmpty else {
            return nil
        }
        self.id = id
        self.event = event
    }

    /// The sentence the human decides by, as the Touch ID would show it.
    public var headline: String {
        event.cause ?? "a program asks to use a credential"
    }

    /// The program's name (`CallerCommand`), or the pid when the agent
    /// could not name it.
    public var program: String {
        if let name = CallerCommand(event.by)?.program {
            return name
        }
        if let pid = event.byPID {
            return "a process (pid \(pid))"
        }
        return "a program"
    }

    public var command: String? {
        event.by
    }

    public var pid: Int32? {
        event.byPID
    }

    public var launchedBy: String? {
        event.launchedBy
    }

    /// True when the identity came from scanning running processes (a mount
    /// reader), which a process running as you could fake, rather than from
    /// the kernel naming the socket peer.
    public var identifiedByScan: Bool {
        event.byLikely ?? false
    }

    /// True for a brokered unlock (jitpass/jit#114): the vault was locked
    /// and a program reached for a secret. Read from the agent's own
    /// wording, which every unlock prompt opens with.
    public var isUnlock: Bool {
        event.cause?.hasPrefix("unlock the vault") ?? false
    }

    /// True when approving also unlocks the vault: on a locked vault, the
    /// agent folds the unlock into a credential or `--with` prompt instead of
    /// asking twice, and says so inside its sentence (agent/consent.go
    /// unlockAsWell). Never at the start, so `isUnlock` stays false for it.
    public var alsoUnlocks: Bool {
        !isUnlock && (event.cause?.contains(" and unlock the vault") ?? false)
    }

    /// What kind of authority the request is for, from the agent's op and
    /// wording.
    public var purpose: String {
        if isUnlock {
            return "unlock the vault: every secret it holds, until it locks again"
        }
        let cause = event.cause ?? ""
        // The larger half leads: the whole vault opens as well, and the bold
        // line is the one read before pressing Allow.
        if alsoUnlocks {
            if event.op == "reveal_pid", cause.hasPrefix("grant this run access to") {
                return "give this run a machine-wide credential file and unlock the vault: every secret it holds, until it locks again"
            }
            return "use a credential and unlock the vault: every secret it holds, until it locks again"
        }
        switch event.op {
        // A standing grant (`jit grant --until-revoked`) has no deadline;
        // the agent's sentence ends "until you revoke it" (agent/grant.go).
        case "grant_create" where cause.contains("until you revoke it"):
            return "create a grant: unattended access until you revoke it"
        case "grant_create": return "create a grant: unattended access until a deadline"
        // reveal_pid carries three prompts (agent/session.go
        // forceDisclosedChallenge): a credential's consent, which is the
        // default below, and these two, told apart by the agent's wording.
        case "reveal_pid" where cause.contains("and everything it launches reach your credentials"):
            return "trust a program: it and everything it launches reach your credentials without asking, until the vault locks"
        case "reveal_pid" where cause.hasPrefix("grant this run access to"):
            return "give this run a machine-wide credential file, for this run only"
        case "grant_extend": return "extend a grant's deadline"
        // A job asks on every run, so "remembered until the vault locks",
        // the default below, is false for it (seen in the first Cowork run).
        case SessionEvent.jobRunOp: return "run an AI job: this run only, and it asks again next time"
        case SessionEvent.jobAllowOp: return "approve an AI job"
        default: return "use a credential once, remembered until the vault locks"
        }
    }

    /// The AI job a job prompt is about, and whether this is a job's run,
    /// which the app shows as that job's own sheet.
    public var job: String? {
        event.job
    }

    public var isJobRun: Bool {
        event.op == SessionEvent.jobRunOp && event.job != nil
    }

    /// How many times this same request was already refused this session,
    /// read from the agent's own "(refused N times)" marker. Zero when the
    /// marker is absent; the headline still shows it either way.
    public var priorRefusals: Int {
        guard let cause = event.cause else {
            return 0
        }
        if cause.contains("(refused once)") {
            return 1
        }
        guard let range = cause.range(of: #"\(refused (\d+) times\)"#, options: .regularExpression) else {
            return 0
        }
        let digits = cause[range].filter(\.isNumber)
        return Int(digits) ?? 0
    }

    public var date: Date {
        event.date
    }

    /// True when the agent is raising the Touch ID for this request now and
    /// awaits no allow: the app shows it beside the dialog, with Deny only.
    /// False from an agent that still asks the app first (the sheet).
    public var touchIDFollows: Bool {
        event.touchIDFollows ?? false
    }

    /// What the app does with a request as it arrives.
    public enum Handling: Equatable, Sendable {
        /// Beside its Touch ID, and the app's own: say it is shown, so the
        /// dialog appears at once, and show nothing.
        case markShown
        /// Beside its Touch ID: the Asking block, then say it is shown.
        case showBeside
        /// An older agent waiting on the app, for the app's own request:
        /// allow, which only lets the agent show its Touch ID.
        case allow
        /// An older agent waiting on the app: the sheet.
        case showSheet
    }

    /// `ours` is a request from this app or a jit it started for a click,
    /// which a dialog in the app already explained. Never `.allow` for a
    /// request beside its Touch ID: an allow there does nothing, and the
    /// agent is waiting for `consent_shown`, not an answer.
    public func handling(ours: Bool) -> Handling {
        switch (touchIDFollows, ours) {
        case (true, true): .markShown
        case (true, false): .showBeside
        case (false, true): .allow
        case (false, false): .showSheet
        }
    }

    /// Whether the outcome event that answers this request (it carries the
    /// same consent id) allowed it: an `approved`, or the `unlock` a
    /// program's unlock request ends in. Anything else refused it.
    public static func allowed(by outcome: SessionEvent) -> Bool {
        outcome.kind == "approved" || outcome.kind == "unlock"
    }
}
