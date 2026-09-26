// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

// AI Jobs, mirrored from `internal/agent/protocol.go` in jitpass/jit
// (design/agent-jobs.md). A job is a command the human approved, with the
// secrets it gets; an AI tool runs it by name, the service runs it, and the
// tool gets the output with every secret value hidden. None of these types
// carries a value or a key: names, paths and state only.

/// A job as a client proposes it to `job_allow` or `job_preview`. The service
/// resolves the executable, the profile's secrets and the fingerprint itself;
/// the human approves what the service resolved, never this.
public struct JobSpec: Codable, Sendable, Equatable {
    public var dir: String
    public var argv: [String]
    public var profile: GrantProfile?
    /// `each-time` or `never`; see `JobAsk`.
    public var ask: String?
    /// Variables whose values may appear in the output. Hidden otherwise.
    public var shown: [String]?
    public var outputs: [String]?
    /// The approving environment's PATH and home: the service runs with
    /// launchd's environment, and the command must run as it did when read.
    public var pathEnv: String
    public var home: String
    public var description: String?
    /// Approve over an existing job of the same name.
    public var replace: Bool?

    public init(
        dir: String, argv: [String], profile: GrantProfile? = nil, ask: String? = nil, shown: [String]? = nil,
        outputs: [String]? = nil, pathEnv: String, home: String, description: String? = nil, replace: Bool? = nil
    ) {
        self.dir = dir
        self.argv = argv
        self.profile = profile
        self.ask = ask
        self.shown = shown
        self.outputs = outputs
        self.pathEnv = pathEnv
        self.home = home
        self.description = description
        self.replace = replace
    }

    enum CodingKeys: String, CodingKey {
        case dir, argv, profile, ask, shown, outputs
        case pathEnv = "path_env"
        case home, description, replace
    }
}

/// When a job asks the human before it runs.
public enum JobAsk: String, Sendable {
    case eachTime = "each-time"
    case never
}

/// One secret a job injects: its variable, its vault path, whether its value
/// may appear in output, and whether it was rotated since approval.
public struct JobSecretStatus: Codable, Sendable, Equatable {
    public var name: String
    public var path: String
    public var shown: Bool?
    public var rotated: Bool?

    public init(name: String, path: String, shown: Bool? = nil, rotated: Bool? = nil) {
        self.name = name
        self.path = path
        self.shown = shown
        self.rotated = rotated
    }

    enum CodingKeys: String, CodingKey {
        case name = "var"
        case path, shown, rotated
    }

    public var isShown: Bool {
        shown == true
    }
}

/// One way a job's folder differs from what was approved.
public struct JobChange: Codable, Sendable, Equatable {
    public var path: String
    /// `changed`, `added`, `removed`, or `rewritten` (same content, but the
    /// file was written to or swapped and put back).
    public var kind: String

    public init(path: String, kind: String) {
        self.path = path
        self.kind = kind
    }
}

/// One approved job, as `job_list` reports it.
public struct JobStatus: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var dir: String
    public var argv: [String]
    public var exe: String?
    public var profile: String?
    /// The profile is read from `~/.jit/profiles`, not the job's folder.
    public var profileGlobal: Bool?
    /// The folder the profile is read from, when it is not global; the job
    /// may run in a folder inside it.
    public var profileRoot: String?
    public var secrets: [JobSecretStatus]?
    public var ask: String?
    public var outputs: [String]?
    public var description: String?
    public var files: Int?
    /// `ready`, `changed` or `rotated`; see `JobState`.
    public var state: String?
    public var changes: [JobChange]?
    public var approvedUnix: Int64?
    public var runs: Int64?
    public var lastRunUnix: Int64?
    public var lastExit: Int?
    public var lastCaller: String?
    public var lastRefusal: String?
    public var lastHidden: Int?
    /// The job won't run until it is approved again. Absent from a jit
    /// older than the field, where `isStopped` reads `state` as before.
    public var stopped: Bool?
    /// Where the job stands, in `JobOutcome`'s words: absent for a job that
    /// runs, and from a jit older than the field.
    public var outcome: String?
    /// How many runs in a row were skipped, and when the first of them was.
    public var skips: Int?
    public var skippingSinceUnix: Int64?

    public var id: String {
        name
    }

    public init(name: String, dir: String, argv: [String], ask: String? = nil, state: String? = nil) {
        self.name = name
        self.dir = dir
        self.argv = argv
        self.ask = ask
        self.state = state
    }

    enum CodingKeys: String, CodingKey {
        case name, dir, argv, exe, profile, secrets, ask, outputs, description, files, state, changes
        case profileGlobal = "profile_global"
        case profileRoot = "profile_root"
        case approvedUnix = "approved_unix"
        case runs
        case lastRunUnix = "last_run_unix"
        case lastExit = "last_exit"
        case lastCaller = "last_caller"
        case lastRefusal = "last_refusal"
        case lastHidden = "last_hidden"
        case stopped, outcome, skips
        case skippingSinceUnix = "skipping_since_unix"
    }

    public var jobState: JobState {
        JobState(rawValue: state ?? "") ?? .ready
    }

    /// jit's own `stopped` when it sends one, so nothing is inferred from
    /// `state`; an older jit's `state`, as before, when it does not.
    public var isStopped: Bool {
        stopped ?? (jobState != .ready)
    }

    /// `outcome` as a `JobOutcome`; nil for a job that runs, for a jit
    /// older than the field, and for a value this app does not know.
    public var jobOutcome: JobOutcome? {
        outcome.flatMap(JobOutcome.init(rawValue:))
    }

    /// What the job's row shows. A job whose skipped runs went on long
    /// enough for jit to tell the owner (`persisting-skip`) is not stopped,
    /// but it has not been running; a lone skip shows nothing new.
    public var rowState: JobRowState {
        if isStopped {
            return .stopped
        }
        return jobOutcome == .persistingSkip ? .notRunning : .ready
    }

    public var asksEachTime: Bool {
        JobAsk(rawValue: ask ?? "") != .never
    }

    public var lastRun: Date? {
        lastRunUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public var approved: Date? {
        approvedUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

/// What a job's row shows: stopped (its amber card), not running (an amber
/// dot and jit's reason on its row), or ready.
public enum JobRowState: Sendable, Equatable {
    case ready
    case stopped
    case notRunning
}

/// What a run that did not happen means for its job, in jit's words
/// (`SessionEvent.job_outcome`, `JobStatus.outcome`). The app decides from
/// this, never from the event's cause.
public enum JobOutcome: String, Sendable {
    /// This run stopped the job: it won't run until approved again.
    case stop
    /// A run of a job already stopped: nothing new, the stop was told.
    case stillStopped = "still-stopped"
    /// This run was skipped for a cause outside the job; the next tries again.
    case skip
    /// Skipped runs that went on, told once per streak. Still not a stop.
    case persistingSkip = "persisting-skip"
}

/// Whether a job can run. Anything but `ready` means stopped until the human
/// approves it again.
public enum JobState: String, Sendable {
    case ready
    case changed
    case rotated
}

/// What approving a job would do, from the same checks `job_allow` runs
/// before its prompt. `refusal`, when set, is approval's own words.
public struct JobPreview: Codable, Sendable, Equatable {
    public var refusal: String?
    public var dir: String?
    public var exe: String?
    public var program: String?
    public var files: Int?
    public var extra: [String]?
    public var secrets: [JobSecretStatus]?
    public var ask: String?
    public var exists: Bool?
    /// The Touch ID sentence approval will show, exactly.
    public var prompt: String?

    public init(refusal: String? = nil) {
        self.refusal = refusal
    }
}

/// A job an agent proposed and the human has not answered. Nothing in it has
/// been resolved or approved.
public struct JobProposal: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var spec: JobSpec
    /// The proposer's own sentence. Show it as theirs, unchecked.
    public var why: String?
    public var by: String?
    public var launchedBy: String?
    public var unixTime: Int64

    enum CodingKeys: String, CodingKey {
        case id, name, spec, why, by
        case launchedBy = "launched_by"
        case unixTime = "unix_time"
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(unixTime))
    }
}

public extension SessionEvent {
    /// An agent's job proposal, streamed to the app; `consentID` carries the
    /// proposal's id and `job` its name.
    static let jobProposalKind = "job_proposal"
    /// The ops of the prompts that are about an AI job.
    static let jobAllowOp = "job_allow"
    static let jobRunOp = "job_run"
}

public extension AgentClient {
    /// Every approved job with its current state. No prompt.
    func jobs() throws -> [JobStatus] {
        try send(AgentRequest(op: .jobList)).jobs ?? []
    }

    /// Approval's checks without the prompt: what approving would do, or the
    /// refusal. Fingerprinting a folder takes time, so this waits longer than
    /// an ordinary read.
    func previewJob(name: String, spec: JobSpec) throws -> JobPreview {
        let response = try send(AgentRequest(op: .jobPreview, jobName: name, jobSpec: spec), timeout: 30)
        guard let preview = response.preview else {
            throw AgentClientError.agent("preview not reported back")
        }
        return preview
    }

    /// Approve a job: the service resolves and fingerprints it and puts up
    /// its own Touch ID. `proposalID` clears the proposal it came from.
    func allowJob(name: String, spec: JobSpec, proposalID: String? = nil) throws -> JobStatus {
        let request = AgentRequest(op: .jobAllow, jobName: name, jobSpec: spec, proposalID: proposalID)
        guard let job = try send(request, timeout: Self.promptTimeout).jobs?.first else {
            throw AgentClientError.agent("job approved but not reported back")
        }
        return job
    }

    /// Remove a job now. No prompt: reducing access is always free.
    /// Returns jit's `key_note` when the job is gone but its key could not
    /// be deleted from here, nil when there was nothing to say.
    @discardableResult
    func removeJob(name: String) throws -> String? {
        try send(AgentRequest(op: .jobRemove, jobName: name)).keyNote.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The proposals waiting for the human. No prompt.
    func jobProposals() throws -> [JobProposal] {
        try send(AgentRequest(op: .jobProposals)).proposals ?? []
    }

    /// Drop a proposal without approving it. No prompt.
    func dismissProposal(id: String) throws {
        _ = try send(AgentRequest(op: .jobDismiss, proposalID: id))
    }
}
