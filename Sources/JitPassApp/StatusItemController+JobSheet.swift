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
        model.jobCancelled = false
        model.jobPreview = nil
        model.jobDraft = prefill
        model.jobTyping = false
        model.jobScripts = JobScripts.suggest(in: prefill.folder)
        if prefill.profile == nil, prefill.folder.isEmpty {
            reloadProfiles()
        }
        reloadJobs()
        aiJobsWindow.present()
        model.jobSheet = true
    }

    /// Edit: the same sheet filled in from the approved job. Nothing
    /// changes until its approval; the job runs as it was until then.
    func editJob(_ job: JobStatus) {
        openJobSheet(prefill: JobDraft(editing: job))
    }

    func openProposal(_ proposal: JobProposal) {
        var draft = JobDraft(proposal: proposal)
        let store = (draft.folder as NSString).appendingPathComponent(ProfileDiscovery.storeSubpath)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: store)) ?? [])
            .filter { $0.hasSuffix(".yaml") }.map { String($0.dropLast(5)) }
        draft.fillProfile(from: names)
        openJobSheet(prefill: draft)
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
        model.jobDraft = model.jobDraft.cleared()
        model.jobPreview = nil
        model.jobTyping = false
        model.jobScripts = []
        reloadProfiles()
    }

    /// The folder the script is in: one inside the profile's folder, or,
    /// for a global profile, any.
    func chooseJobFolder() {
        guard let folder = chooseDirectory(message: "Choose the folder the script is in") else {
            return
        }
        model.jobDraft.choose(folder: folder)
        model.jobPreview = nil
        model.jobTyping = false
        model.jobScripts = JobScripts.suggest(in: folder)
    }

    private func chooseDirectory(message: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = message
        if let start = [model.jobDraft.folder, model.jobDraft.profileRoot ?? ""].first(where: { !$0.isEmpty }) {
            panel.directoryURL = URL(fileURLWithPath: start)
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
        approved.replace = spec.replace ?? (model.jobPreview?.exists == true ? true : nil)
        let client = client
        model.jobBusy = true
        model.jobError = nil
        model.jobCancelled = false
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
                    model.jobsBanner = draft.editing == nil ? Format.approvedJobBanner(job) : Format.approvedEditBanner(job)
                    model.jobsBannerFailed = false
                    reloadJobs()
                    aiJobsWindow.reclaimFocus()
                case let .failure(error):
                    model.jobCancelled = Format.isTouchIDCancel(error)
                    model.jobError = model.jobCancelled ? nil : Format.error(error)
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
        guard model.notifyJobs else {
            return
        }
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
        guard model.notifyJobs, let name = event.job, let cause = event.cause, cause.contains("refused") else {
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
            remove: { [weak self] in
                guard let self, let job = model.jobReview?.job else {
                    return
                }
                closeJobReview()
                confirmRemove(job)
            },
            cancel: { [weak self] in self?.closeJobReview() }
        )
    }

    func openJobReview(_ job: JobStatus) {
        let review = JobReview(job: job)
        model.jobReview = review
        model.jobReviewDiff = nil
        model.jobReviewTracked = []
        model.jobError = nil
        model.jobCancelled = false
        model.jobReviewSheet = true
        let files = review.items.compactMap(\.file)
        Task.detached {
            let tracked = Set(files.filter { Self.gitTracks($0) })
            await MainActor.run { [weak self] in
                self?.model.jobReviewTracked = tracked
            }
        }
    }

    /// Closes the review. What it showed is cleared once the sheet is gone
    /// (`jobReviewDismissed`): clearing it here emptied the sheet's content
    /// before macOS had closed it, and Cancel left it stuck open.
    func closeJobReview() {
        model.jobReviewSheet = false
        model.jobError = nil
    }

    func jobReviewDismissed() {
        model.jobReview = nil
        model.jobReviewDiff = nil
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
        model.jobCancelled = false
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
                    model.jobCancelled = Format.isTouchIDCancel(error)
                    model.jobError = model.jobCancelled ? nil : Format.error(error)
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
