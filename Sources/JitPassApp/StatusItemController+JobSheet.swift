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
            chooseFolder: { [weak self] in self?.chooseJobFolder() },
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
        model.jobProfiles = Self.profiles(in: prefill.folder)
        if model.jobDraft.profile == nil {
            model.jobDraft.profile = model.jobProfiles.count == 1 ? model.jobProfiles.first : nil
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

    /// The profiles a folder's `.jit/profiles` holds, by name.
    nonisolated static func profiles(in folder: String) -> [String] {
        guard !folder.isEmpty else {
            return []
        }
        let dir = (folder as NSString).appendingPathComponent(".jit/profiles")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { $0.hasSuffix(".yaml") }.map { String($0.dropLast(5)) }.sorted()
    }

    // MARK: - Choosing folders

    func chooseJobFolder() {
        guard let folder = chooseDirectory(message: "Choose the folder the job runs in") else {
            return
        }
        model.jobDraft.folder = folder
        if model.jobDraft.name.isEmpty {
            model.jobDraft.name = JobDraft.suggestedName(folder: folder)
        }
        model.jobProfiles = Self.profiles(in: folder)
        model.jobDraft.profile = model.jobProfiles.count == 1 ? model.jobProfiles.first : nil
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
        let name = draft.name.isEmpty ? JobDraft.suggestedName(folder: draft.folder) : draft.name
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
