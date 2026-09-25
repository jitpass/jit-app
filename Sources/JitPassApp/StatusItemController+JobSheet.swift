// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// New AI Job: the sheet, its live preview, the approval, and agents'
/// proposals (the Jobs mockup, frames C, D, E and H). The sheet collects the
/// request exactly as `jit job allow` does; `job_preview` runs approval's own
/// checks as the human types; `job_allow` puts up the service's Touch ID. An
/// agent's proposal arrives on the event stream, is announced once, and opens
/// the same sheet pre-filled.
extension StatusItemController {
    var jobSheetActions: JobSheetActions {
        JobSheetActions(
            preview: { [weak self] in self?.previewJobSoon() },
            chooseProfile: { [weak self] profile in self?.chooseJobProfile(profile) },
            changeProfile: { [weak self] in self?.changeJobProfile() },
            chooseFolder: { [weak self] in self?.chooseJobFolder() },
            addFolder: { [weak self] in self?.chooseProfileFolder() },
            chooseOutput: { [weak self] in self?.chooseJobOutput() },
            approve: { [weak self] in self?.approveJob() },
            cancel: { [weak self] in self?.closeJobSheet() },
            dismiss: { [weak self] in self?.dismissJobProposal() }
        )
    }

    /// The window first, then the sheet from its title bar, as New Grant.
    func openJobSheet(prefill: JobDraft = JobDraft()) {
        panel.dismiss()
        model.jobsBanner = nil
        model.jobError = nil
        model.jobPreview = nil
        model.jobDraft = prefill
        model.jobTyping = false
        model.jobMoreOptions = false
        model.jobScripts = JobScripts.suggest(in: prefill.folder)
        if prefill.profile == nil, prefill.folder.isEmpty {
            reloadProfiles()
        }
        reloadJobs()
        aiJobsWindow.present()
        model.jobSheet = true
    }

    func openProposal(_ proposal: JobProposal) {
        openJobSheet(prefill: JobDraft(proposal: proposal))
    }

    func closeJobSheet() {
        model.jobSheet = false
        model.jobError = nil
        model.jobPreview = nil
        previewTask?.cancel()
    }

    // MARK: - Choosing

    /// A profile sets the folder, and the folder's scripts are what Runs
    /// offers.
    func chooseJobProfile(_ profile: DiscoveredProfile) {
        model.jobDraft.choose(profile: profile)
        model.jobPreview = nil
        model.jobTyping = false
        model.jobScripts = JobScripts.suggest(in: model.jobDraft.folder)
    }

    /// Back to the list, dropping what was chosen for the last profile.
    func changeJobProfile() {
        var draft = JobDraft()
        draft.ask = model.jobDraft.ask
        model.jobDraft = draft
        model.jobPreview = nil
        model.jobTyping = false
        model.jobScripts = []
        reloadProfiles()
    }

    /// Only for a global profile, which names no folder of its own.
    func chooseJobFolder() {
        guard let folder = chooseDirectory(message: "Choose the folder the job runs in") else {
            return
        }
        model.jobDraft.folder = folder
        model.jobDraft.command = ""
        model.jobScripts = JobScripts.suggest(in: folder)
    }

    func chooseJobOutput() {
        if let folder = chooseDirectory(message: "Choose the folder the job writes into") {
            model.jobDraft.output = folder
        }
    }

    private func chooseDirectory(message: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = message
        if !model.jobDraft.folder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: model.jobDraft.folder)
        }
        return panel.runFrontmost() == .OK ? panel.url?.path : nil
    }

    // MARK: - The preview

    /// `job_preview` a moment after the typing stops: approval's own checks,
    /// no prompt. An older answer never lands over a newer draft.
    func previewJobSoon() {
        previewTask?.cancel()
        let draft = model.jobDraft
        guard !draft.folder.isEmpty, !draft.argv.isEmpty else {
            model.jobPreview = nil
            return
        }
        let spec = draft.spec(pathEnv: JitCLI.environment["PATH"] ?? "", home: NSHomeDirectory())
        let name = JobDraft.isValidName(draft.name) ? draft.name : JobDraft.suggestedName(folder: draft.folder)
        let client = client
        model.jobPreviewBusy = true
        previewTask = Task.detached {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled {
                return
            }
            let preview: JobPreview? = try? client.previewJob(name: name, spec: spec)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled, model.jobDraft == draft else {
                    return
                }
                model.jobPreview = preview
                model.jobPreviewBusy = false
            }
        }
    }

    // MARK: - Approve, dismiss

    func approveJob() {
        let draft = model.jobDraft
        guard draft.isComplete, model.jobPreview?.refusal == nil else {
            return
        }
        let spec = draft.spec(pathEnv: JitCLI.environment["PATH"] ?? "", home: NSHomeDirectory())
        var approved = spec
        approved.replace = model.jobPreview?.exists == true ? true : nil
        let client = client
        model.jobBusy = true
        model.jobError = nil
        Task.detached {
            let result = Result { try client.allowJob(name: draft.name, spec: approved, proposalID: draft.proposal?.id) }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.jobBusy = false
                switch result {
                case let .success(job):
                    closeJobSheet()
                    model.jobsBanner = Format.approvedJobBanner(job)
                    model.jobsBannerFailed = false
                    reloadJobs()
                    aiJobsWindow.reclaimFocus()
                case let .failure(error):
                    model.jobError = Format.error(error)
                    aiJobsWindow.reclaimFocus()
                }
            }
        }
    }

    func dismissJobProposal() {
        if let id = model.jobDraft.proposal?.id {
            try? client.dismissProposal(id: id)
        }
        closeJobSheet()
        reloadJobs()
    }

    // MARK: - Proposals and stops, from the stream

    /// An agent proposed a job: announce it once, and keep the window's list
    /// current. Nothing is created until the human approves it.
    func receive(jobProposal event: SessionEvent) {
        reloadJobs()
        let who = event.launchedBy ?? "An AI tool"
        Notifier.post(
            title: "\(who) asks to add a job",
            body: "\(event.job ?? "A job"). Click to review.",
            id: "job-proposal-\(event.consentID ?? "\(event.unixTime)")",
            thread: "jobs",
            target: .jobs
        )
    }

    /// A job that refused to run is something only the human can answer.
    /// One notification per job and approval: a caller retrying a stopped
    /// job replaces it rather than stacking more.
    func noteJobStop(_ event: SessionEvent) {
        guard let name = event.job, let cause = event.cause, cause.contains("refused") else {
            return
        }
        let why = cause.components(separatedBy: "refused, ").last ?? cause
        Notifier.post(
            title: "\(name) stopped running",
            body: why.prefix(1).uppercased() + why.dropFirst() + ". Click to review.",
            id: "job-stopped-\(name)",
            thread: "jobs",
            target: .jobs
        )
    }
}

// MARK: - Review a stopped job

extension StatusItemController {
    var jobReviewActions: JobReviewActions {
        JobReviewActions(
            showChanges: { [weak self] file in self?.showJobChanges(file) },
            openFile: { file in NSWorkspace.shared.open(URL(fileURLWithPath: file)) },
            approveAgain: { [weak self] in self?.approveJobAgain() },
            cancel: { [weak self] in self?.closeJobReview() }
        )
    }

    func openJobReview(_ job: JobStatus) {
        let review = JobReview(job: job)
        model.jobReview = review
        model.jobReviewDiff = nil
        model.jobReviewTracked = []
        model.jobError = nil
        model.jobReviewSheet = true
        let files = review.items.compactMap(\.file)
        Task.detached {
            let tracked = Set(files.filter { Self.gitTracks($0) })
            await MainActor.run { [weak self] in
                self?.model.jobReviewTracked = tracked
            }
        }
    }

    func closeJobReview() {
        model.jobReviewSheet = false
        model.jobReview = nil
        model.jobReviewDiff = nil
        model.jobError = nil
    }

    func showJobChanges(_ file: String) {
        Task.detached {
            let diff = Self.gitDiff(file)
            await MainActor.run { [weak self] in
                self?.model.jobReviewDiff = diff
            }
        }
    }

    func approveJobAgain() {
        guard let review = model.jobReview else {
            return
        }
        let spec = review.reapproval(pathEnv: JitCLI.environment["PATH"] ?? "", home: NSHomeDirectory())
        let name = review.job.name
        let client = client
        model.jobBusy = true
        model.jobError = nil
        Task.detached {
            let result = Result { try client.allowJob(name: name, spec: spec) }
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.jobBusy = false
                switch result {
                case let .success(job):
                    closeJobReview()
                    model.jobsBanner = Format.approvedJobBanner(job)
                    model.jobsBannerFailed = false
                    reloadJobs()
                case let .failure(error):
                    model.jobError = Format.error(error)
                }
                aiJobsWindow.reclaimFocus()
            }
        }
    }

    /// Whether git tracks the file: `git ls-files --error-unmatch` in its
    /// folder. False for anything git cannot answer about.
    nonisolated static func gitTracks(_ file: String) -> Bool {
        git(["ls-files", "--error-unmatch", "--", (file as NSString).lastPathComponent], in: file)?.status == 0
    }

    /// `git diff` of one file against its last commit, capped: a review
    /// needs the change, not a megabyte of it.
    nonisolated static func gitDiff(_ file: String) -> String {
        guard let result = git(["diff", "--no-color", "HEAD", "--", (file as NSString).lastPathComponent], in: file),
              result.status == 0
        else {
            return "git could not show the changes for this file."
        }
        let text = result.output.isEmpty ? "No difference from git's last commit: the file was rewritten with the same content." : result
            .output
        return String(text.prefix(20000))
    }

    private nonisolated static func git(_ arguments: [String], in file: String) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", (file as NSString).deletingLastPathComponent] + arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
