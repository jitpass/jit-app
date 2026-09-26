// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What a `job_run` run that did not happen tells the owner, decided here
/// where it is tested: the words and whether there are any. jit says what
/// the run means in `job_outcome`, and only a stop, or skipped runs that
/// went on, is news. A jit older than the field is read from its cause,
/// exactly as before.
public struct JobNotice: Equatable, Sendable {
    public enum Kind: Sendable {
        /// The job stopped: it won't run until approved again.
        case stopped
        /// The job is not stopped, but its last runs did not happen.
        case notRunning
    }

    public var kind: Kind
    public var job: String
    public var title: String
    public var body: String

    /// One notification per job and kind: a stopped job retried replaces
    /// its notice rather than stacking more.
    public var id: String {
        switch kind {
        case .stopped: "job-stopped-\(job)"
        case .notRunning: "job-not-running-\(job)"
        }
    }

    /// Nil when the event is nothing to announce: a run of a job already
    /// stopped (told when it stopped), a lone skip (the next run tries
    /// again), an outcome this app does not know, or no job named.
    public init?(event: SessionEvent) {
        guard let name = event.job, let cause = event.cause else {
            return nil
        }
        guard let outcome = event.jobOutcome else {
            // A jit older than `job_outcome`: its cause's words, as before.
            guard cause.contains("refused") else {
                return nil
            }
            self = Self.stopped(name, cause: cause)
            return
        }
        switch JobOutcome(rawValue: outcome) {
        case .stop:
            self = Self.stopped(name, cause: cause)
        case .persistingSkip:
            self = Self.notRunning(name, cause: cause)
        case .stillStopped, .skip, nil:
            return nil
        }
    }

    init(kind: Kind, job: String, title: String, body: String) {
        self.kind = kind
        self.job = job
        self.title = title
        self.body = body
    }

    /// "<name>: refused, <why>": the why, as the notification always said it.
    private static func stopped(_ name: String, cause: String) -> JobNotice {
        let why = cause.components(separatedBy: "refused, ").last ?? cause
        return JobNotice(kind: .stopped, job: name, title: "\(name) stopped running", body: sentence(why) + ". Click to review.")
    }

    /// "<name>: didn't run 3 times in a row since Sep 26 09:14, <why>": jit's
    /// own sentence after the name, and that the job was not stopped.
    private static func notRunning(_ name: String, cause: String) -> JobNotice {
        let prefix = "\(name): "
        let said = cause.hasPrefix(prefix) ? String(cause.dropFirst(prefix.count)) : cause
        return JobNotice(
            kind: .notRunning, job: name,
            title: "\(name) hasn't been running",
            body: sentence(said) + ". It wasn't stopped: the next run tries again."
        )
    }

    private static func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
