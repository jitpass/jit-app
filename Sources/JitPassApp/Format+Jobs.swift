// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// The AI Jobs window's words, in one place. The drawing they follow is the
/// Jobs mockup (docs/design/mockups/Jobs.html, jit design/agent-jobs.md).
extension Format {
    // MARK: - The window

    static func jobsHeadline(_ board: JobsBoard) -> String {
        if board.isEmpty, board.proposals.isEmpty {
            return "AI Jobs"
        }
        var head = jobsCount(board.jobCount)
        if board.needsYou > 0 {
            head += " · " + (board.needsYou == 1 ? "1 needs you" : "\(board.needsYou) need you")
        }
        return head
    }

    static func jobsSubline(_ board: JobsBoard) -> String {
        board.isEmpty
            ? "A job lets AI tools run one command with secrets. They see what it prints, never the values."
            : "Each runs only as you approved it. A changed file stops it until you look."
    }

    static let jobsEmptyTitle = "No AI tool can run anything with your secrets"
    static let jobsEmptyMessage = "Approve a job when you want Claude or another agent to run a script that needs a key, " +
        "without being able to read the key."

    static func jobsCount(_ n: Int) -> String {
        n == 1 ? "1 job" : "\(n) jobs"
    }

    /// The footer states; it configures nothing.
    static func jobsFooter(_ board: JobsBoard) -> String {
        let runs = board.runs == 1 ? "1 run" : "\(board.runs) runs"
        return jobsCount(board.jobCount) + " · " + runs + " since each was approved"
    }

    // MARK: - A stopped job

    static func jobStoppedEyebrow(_ job: JobStatus) -> String {
        job.jobState == .rotated ? "Rotated" : "Changed"
    }

    static func jobStoppedTitle(_ job: JobStatus) -> String {
        "\(job.name) stopped running"
    }

    /// What stopped it, in the service's own words, and the way back.
    static func jobStoppedNote(_ job: JobStatus) -> String {
        let why: String = if let change = job.changes?.first {
            change.kind == "rewritten"
                ? "\(change.path) was written to since you approved it, though its content matches"
                : "\(change.path) \(change.kind) since you approved it"
        } else if let refusal = job.lastRefusal, !refusal.isEmpty {
            refusal
        } else {
            job.jobState == .rotated ? "A secret it uses was rotated" : "Its files changed"
        }
        return why + ". jit refuses the job until you look at the change and approve it again."
    }

    // MARK: - A job's row

    /// "· python list_guest_users.py": the program's name and its arguments.
    static func jobCommand(_ job: JobStatus) -> String {
        guard let first = job.argv.first else {
            return ""
        }
        let program = (first as NSString).lastPathComponent
        return "· " + ([program] + job.argv.dropFirst()).joined(separator: " ")
    }

    static func jobAsks(_ job: JobStatus) -> String {
        job.asksEachTime ? "Asks each time" : "Runs without asking"
    }

    static func jobFact(_ job: JobStatus, now: Date = Date()) -> String {
        var parts: [String] = []
        if job.jobState != .ready {
            if let caller = job.lastCaller, !caller.isEmpty {
                parts.append("Refused \(caller)")
            } else {
                parts.append("Stopped")
            }
        } else if let last = job.lastRun {
            let who = job.lastCaller.map { $0.isEmpty ? "An AI tool" : $0 } ?? "An AI tool"
            parts.append("\(who) ran it \(ago(last, now: now))")
            parts.append(job.lastExit.map { $0 == 0 ? "worked" : "exit \($0)" } ?? "worked")
            if let hidden = job.lastHidden, hidden > 0 {
                parts.append(hidden == 1 ? "hid 1 value" : "hid \(hidden) values")
            }
        } else {
            parts.append("Not run yet")
        }
        parts.append(jobAsks(job))
        if let count = job.secrets?.count, count > 0 {
            parts.append(count == 1 ? "1 secret" : "\(count) secrets")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - The AI apps that can ask

    static let jobsAppsEyebrow = "AI apps that can ask"

    static func claudeDesktopFact(_ status: MCPStatus?) -> String {
        guard let status else {
            return "Checking…"
        }
        if status.isConnected {
            return "Connected · Cowork asks through jit mcp"
        }
        return status.installed ? "Set up for a jit that is no longer there" : "Not connected"
    }

    static let terminalAgentsFact = "Always · claude, codex and others ask with jit job run"

    // MARK: - Remove, connect

    static func removeJobTitle(_ job: JobStatus) -> String {
        "Remove \(job.name)?"
    }

    /// Leads with what happens, then what undoing it costs.
    static func removeJobMessage(_ job: JobStatus) -> String {
        var text = "AI tools can no longer run it."
        if !job.asksEachTime {
            text += " Its key is deleted."
        }
        return text + " Approving it again is a new Touch ID, not an undo."
    }

    static func removedJobBanner(_ job: JobStatus) -> String {
        "Removed \(job.name). AI tools can no longer run it."
    }

    static let connectedBanner = "Claude Desktop will start jit's MCP server. Quit and reopen Claude Desktop to pick this up."
    static let disconnectedBanner = "Claude Desktop no longer starts jit's MCP server. Quit and reopen Claude Desktop to pick this up."
}

// MARK: - New AI Job

extension Format {
    static let jobSheetTitle = "New AI Job"
    static let jobRefusedName = "jit won't approve this"
    static let jobFailure = "Nothing was approved"
    static let jobFooterWaiting = "Waiting for Touch ID. The service is asking, not this app."
    static let jobOutputHint = "The tool is told which new files appear here. It gets paths, never their contents."

    /// The sentence at the top, from what the service resolved when it has,
    /// else from what is typed. It says what the approval will mean.
    static func jobSentence(_ draft: JobDraft, preview: JobPreview?) -> String {
        let program = preview?.program ?? draft.argv.first.map { ($0 as NSString).lastPathComponent } ?? "a command"
        let folder = draft.folder.isEmpty ? "a folder" : (draft.folder as NSString).lastPathComponent
        let count = preview?.secrets?.count ?? 0
        let secrets = count == 0 ? "no secrets" : (count == 1 ? "1 secret" : "\(count) secrets")
        return "Let AI tools run \(program) in \(folder) with \(secrets). They see what it prints, never the values."
    }

    static func proposalBanner(_ proposal: JobProposal) -> String {
        "\(proposal.launchedBy ?? "An AI tool") asks you to approve this job. Nothing runs until you do."
    }

    static func proposalWhyHint(_ proposal: JobProposal?) -> String {
        "Written by \(proposal?.launchedBy ?? "the AI tool"). jit does not check it."
    }

    static func jobRunsHint(_: JobDraft, preview: JobPreview?) -> String {
        if let exe = preview?.exe {
            return "Runs \(home(exe)), exactly as typed, with no arguments added"
        }
        return "Exactly this, in the folder above, with no arguments added"
    }

    static func jobSecretsHint(_ draft: JobDraft, preview: JobPreview?, profiles: [String]) -> String {
        guard let profile = draft.profile else {
            return profiles.isEmpty ? "This folder has no jit profile, so the job gets no secrets." : "Choose the profile the job uses."
        }
        if preview?.secrets?.isEmpty ?? true {
            return "From profile \(profile)."
        }
        return "From profile \(profile), as it is now. Editing \(profile).yaml later changes nothing here."
    }

    static func jobAskHint(_ ask: JobAsk) -> String {
        ask == .eachTime
            ? "Touch ID for every run, naming who asked."
            : "No Touch ID after this one, until you remove it. For a job you want to run while you are away."
    }

    static func jobNotes(_ draft: JobDraft, preview: JobPreview?) -> [String] {
        let files = preview?.files ?? 0
        let count = preview?.secrets?.count ?? 0
        var notes = ["jit fingerprints this folder now: \(files == 1 ? "1 file" : "\(files) files"). " +
            "Change any of them and the job stops until you approve it again."]
        if count > 0 {
            notes
                .append(
                    "The script runs with only these \(count == 1 ? "1 secret" : "\(count) secrets"), " +
                        "never anything from the tool that asked."
                )
        }
        if preview?.exists == true {
            notes.append("This replaces the job already named \(draft.name).")
        }
        notes.append("Remove it any time from the AI Jobs window. That never asks.")
        return notes
    }

    static func jobFooter(_ draft: JobDraft, preview: JobPreview?, checking: Bool) -> String {
        if let missing = draft.missing {
            return missing
        }
        if checking || preview == nil {
            return "Checking the job…"
        }
        return preview?.refusal == nil ? "Touch ID follows. The service decides, not this app." : "Nothing to approve"
    }

    static func approvedJobBanner(_ job: JobStatus) -> String {
        let files = job.files ?? 0
        return "Approved \(job.name) · \(files == 1 ? "1 file" : "\(files) files") fingerprinted. AI tools run it by name."
    }

    // MARK: - Proposals in the window

    static func proposalTitle(_ proposal: JobProposal) -> String {
        "\(proposal.launchedBy ?? "An AI tool") asks to add \(proposal.name)"
    }

    static func proposalFact(_ proposal: JobProposal, now: Date = Date()) -> String {
        "Proposed \(ago(proposal.date, now: now)) · nothing runs until you approve it"
    }
}

// MARK: - Review

extension Format {
    static func reviewSentence(_ review: JobReview) -> String {
        let when = review.job.approved.map { " on " + stamp($0, withDay: true) } ?? ""
        if review.items.isEmpty {
            let why = review.job.lastRefusal.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "It stopped"
            return why + ". It won't run until you approve it again."
        }
        let count = review.items.count == 1 ? "1 file" : "\(review.items.count) files"
        return "\(count) changed since you approved this job\(when). It won't run until you approve it again."
    }

    static func reviewFact(_ item: JobReview.Item, tracked: Set<String>) -> String {
        switch item.kind {
        case "removed": return "Removed since approval"
        case "added": return "Added since approval"
        case "rewritten": return "Written to since approval; its content matches, but something rewrote it or swapped it back"
        default:
            guard let file = item.file else {
                return "Changed since approval"
            }
            return tracked.contains(file) ? "Changed since approval · in git" : "Changed since approval · not in git"
        }
    }

    static let reviewNotes = [
        "jit keeps fingerprints, not copies, so it can name a changed file but not show what it was before. " +
            "Git can, where the folder has it.",
        "A library edit is as able to leak a key as a script edit. If you did not expect this change, don't approve it."
    ]
}

// MARK: - A job's run, brokered

extension Format {
    static func jobRunTitle(_ request: ConsentRequest) -> String {
        "\(request.launchedBy ?? request.program) asks to run an AI job"
    }

    static func jobRunSentence(_ request: ConsentRequest, job: JobStatus?) -> String {
        let who = request.launchedBy ?? request.program
        let count = job?.secrets?.count ?? 0
        let secrets = count == 1 ? "1 secret" : "\(count) secrets"
        return "Run \(request.job ?? "this job") with \(secrets). \(who) sees what it prints, never the values."
    }

    static func jobRunFolder(_ job: JobStatus) -> String {
        let state = job.jobState == .ready
            ? "unchanged since you approved it" + (job.approved.map { " on " + stamp($0, withDay: true) } ?? "")
            : "changed since you approved it"
        return "In \(home(job.dir)) · \(state)"
    }

    static func jobRunSecrets(_ job: JobStatus) -> String {
        let secrets = job.secrets ?? []
        let hidden = secrets.filter { !$0.isShown }.map(\.name)
        let shown = secrets.filter(\.isShown).map(\.name)
        var parts: [String] = []
        if !hidden.isEmpty {
            parts.append(hidden.joined(separator: ", ") + " hidden")
        }
        if !shown.isEmpty {
            parts.append(shown.joined(separator: ", ") + " shown")
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " · ")
    }

    static func jobRunNotes(_ request: ConsentRequest) -> [String] {
        let who = request.launchedBy ?? request.program
        return [
            "This run only. The job asks again next time.",
            "Allow: macOS asks for Touch ID next. Deny: \(who) gets an error and nothing runs."
        ]
    }
}

// MARK: - AI Agents: what each agent can run

extension Format {
    /// "3 AI jobs, never seeing their keys · ran notion-guests 5 minutes ago".
    /// The last run is this agent's own, matched on the name the service
    /// recorded for who asked ("claude" for the CLI, "Claude" for the app).
    static func agentCanRun(caller: String, jobs: [JobStatus], now: Date = Date()) -> String {
        guard !jobs.isEmpty else {
            return "No AI jobs yet"
        }
        var text = (jobs.count == 1 ? "1 AI job" : "\(jobs.count) AI jobs") + ", never seeing their keys"
        let mine = jobs.filter { $0.lastCaller == caller && $0.lastRun != nil }
        if let last = mine.max(by: { ($0.lastRunUnix ?? 0) < ($1.lastRunUnix ?? 0) }), let when = last.lastRun {
            text += " · ran \(last.name) \(ago(when, now: now))"
        }
        return text
    }

    static let claudeDesktopNote = "An app, not a command line tool. Its Cowork shell runs in a Linux VM, so it can't run jit itself. " +
        "It asks through AI Jobs."
    static let claudeDesktopNotConnectedNote = "Installed, but its Cowork shell can't reach jit. " +
        "Connect it and Claude can run scripts you approve, without seeing their keys."
    static let claudeDesktopAsksThrough = "jit mcp, in Claude Desktop's settings"
    static let onboardingClaudeDesktopTitle = "Let Claude Desktop run your scripts without seeing keys"
    static let onboardingClaudeDesktopDetail = "Lets Claude ask to run your scripts. You approve each one first."
}
