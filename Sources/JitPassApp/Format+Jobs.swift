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
        if board.runs == 0 {
            return jobsCount(board.jobCount) + " · none run yet"
        }
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
    /// What tells two jobs apart on their row: the script an interpreter
    /// runs (`list_guest_users.py`), else the program. The whole command is
    /// on the review sheet; cut from the front here, it read as "…ython".
    static func jobCommand(_ job: JobStatus) -> String {
        guard let first = job.argv.first else {
            return ""
        }
        let script = job.argv.count > 1 && !job.argv[1].hasPrefix("-") ? job.argv[1] : first
        return "· " + (script as NSString).lastPathComponent
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

    static func mcpFact(_ app: MCPApp, _ status: MCPStatus?) -> String {
        guard let status else {
            return "Checking…"
        }
        if status.isConnected {
            return "Connected · " + app.via
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

    static func mcpChangedBanner(_ app: MCPApp, connected: Bool) -> String {
        (connected ? "\(app.name) will start jit's MCP server." : "\(app.name) no longer starts jit's MCP server.") +
            " Quit and reopen \(app.name) to pick this up."
    }

    static func disconnectMessage(_ app: MCPApp) -> String {
        "\(app.name)'s agent can no longer list or run your AI jobs. Your jobs stay; connecting again brings them back."
    }
}

// MARK: - New AI Job

extension Format {
    /// "New AI Job", or the job's name when editing it.
    static func jobSheetTitle(_ draft: JobDraft) -> String {
        draft.editing.map { "Edit \($0.name)" } ?? "New AI Job"
    }

    static let jobRefusedName = "jit won't approve this"
    static let jobFailure = "Nothing was approved"
    static let jobFooterWaiting = "Waiting for Touch ID…"
    static let jobOutputHint = "The tool is told which new files appear here. It gets paths, never their contents."

    static let jobNoProfiles = "jit found no profiles on this Mac. A job gets its secrets from one: " +
        "protect a project's .env first, or add the folder that holds one."
    static let jobGlobalProfileHint = "A profile from ~/.jit/profiles names no folder."
    static let jobTypingHint = "Type it as you would in a terminal in this folder"
    static let jobShownHint = "Every value is hidden in what the tool sees. " +
        "Show one only when it is configuration the script prints, never a key."
    static let jobNameHint = "What AI tools call it: lowercase letters, digits and dashes."

    static func jobScriptsHint(_ scripts: [JobScript], folder: String) -> String {
        if scripts.isEmpty {
            return "No scripts at the top of \(home(folder)). Type the command instead."
        }
        if scripts.contains(where: { $0.argv.first?.hasPrefix(".venv/") == true || $0.argv.first?.hasPrefix("venv/") == true }) {
            return "The scripts in this folder. jit saw its virtualenv, so Python runs from it."
        }
        return "The scripts in this folder."
    }

    /// The closed More options line, with both values on it.
    static func jobMoreOptions(_ draft: JobDraft) -> String {
        let output = draft.output.isEmpty ? "no output folder" : "output in " + (draft.output as NSString).lastPathComponent
        if draft.editing != nil {
            return "More options · \(output)"
        }
        let name = draft.name.isEmpty ? "not named yet" : "named \(draft.name)"
        return "More options · \(name) · \(output)"
    }

    static func proposalBanner(_ proposal: JobProposal) -> String {
        "\(proposal.launchedBy ?? "An AI tool") asks you to approve this job. Nothing runs until you do."
    }

    static func proposalWhyHint(_ proposal: JobProposal?) -> String {
        "Written by \(proposal?.launchedBy ?? "the AI tool"). jit does not check it."
    }

    /// Where the program was found only when the command does not already
    /// say it: `python3` is resolved on PATH, `.venv/bin/python` is not.
    static func jobRunsHint(_ draft: JobDraft, preview: JobPreview?) -> String {
        if let exe = preview?.exe, let first = draft.argv.first, !first.contains("/") {
            return "Exactly this, with no arguments added. \(first) is \(home(exe))."
        }
        return "Exactly this, with no arguments added."
    }

    static func jobAskHint(_ ask: JobAsk) -> String {
        ask == .eachTime
            ? "Touch ID for every run, naming who asked."
            : "No Touch ID after this one, until you remove it. For a job you want to run while you are away."
    }

    static func jobNotes(_ draft: JobDraft, preview: JobPreview?) -> [String] {
        let files = preview?.files ?? 0
        if draft.editing != nil {
            return [
                "Changed: " + draft.changes.joined(separator: " · ") + ".",
                "Approving fingerprints the folder as it is now (\(files == 1 ? "1 file" : "\(files) files")), " +
                    "and the job's run count starts over.",
                "Until you approve, it runs as it was."
            ]
        }
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
        return preview?.refusal == nil ? "Touch ID follows." : "Nothing to approve"
    }

    static func approvedEditBanner(_ job: JobStatus) -> String {
        let files = job.files ?? 0
        return "Approved the changes to \(job.name) · \(files == 1 ? "1 file" : "\(files) files") fingerprinted again."
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
