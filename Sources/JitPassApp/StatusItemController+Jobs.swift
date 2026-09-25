// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// AI Jobs (jit design/agent-jobs.md): the window, removing a job, and
/// connecting Claude Desktop. The app shows and asks; the service decides,
/// and every action here is one the CLI can also take: `job_list` and
/// `job_remove` over the socket, `jit mcp install` / `uninstall` through
/// JitCLI.
extension StatusItemController {
    var aiJobsActions: AIJobsActions {
        AIJobsActions(
            reload: { [weak self] in self?.reloadJobs() },
            remove: { [weak self] job in self?.confirmRemove(job) },
            edit: { [weak self] job in self?.editJob(job) },
            newJob: { [weak self] in self?.openJobSheet() },
            review: { [weak self] proposal in self?.openProposal(proposal) },
            reviewJob: { [weak self] job in self?.openJobReview(job) },
            connect: { [weak self] app in self?.setMCP(app, connected: true) },
            disconnect: { [weak self] app in self?.confirmDisconnect(app) },
            fit: { [weak self] height in self?.aiJobsWindow.fit(to: height) }
        )
    }

    func openAIJobs() {
        panel.dismiss()
        model.jobsBanner = nil
        reloadJobs()
        aiJobsWindow.present()
    }

    /// A notification's click: the window, and the oldest waiting proposal's
    /// sheet when there is one.
    func openAIJobsForAttention() {
        openAIJobs()
        let client = client
        Task.detached {
            let proposals = (try? client.jobProposals()) ?? []
            await MainActor.run { [weak self] in
                if let first = proposals.min(by: { $0.unixTime < $1.unixTime }) {
                    self?.openProposal(first)
                }
            }
        }
    }

    /// Off the main thread: listing re-fingerprints every job folder, which
    /// is what makes "changed" true the moment it is, and takes a moment.
    func reloadJobs() {
        let client = client
        let installed = MCPApp.allCases.filter { FileManager.default.fileExists(atPath: $0.appPath) }
        model.installedApps = Set(installed.map(\.id))
        Task.detached {
            let jobs = (try? client.jobs()) ?? []
            let proposals = (try? client.jobProposals()) ?? []
            var status: [String: MCPStatus] = [:]
            for app in installed {
                status[app.id] = try? JitCLI.document(app.arguments("status") + ["--format", "json"]) {
                    try JSONDecoder().decode(MCPStatus.self, from: Data($0.utf8))
                }.get()
            }
            await MainActor.run { [weak self] in
                self?.model.jobs = jobs
                self?.model.jobProposals = proposals
                self?.model.mcpStatus = status
            }
        }
    }

    /// Remove asks once, leading with what happens. Remove is the default:
    /// reducing access is meant to stay the easiest thing in the window.
    func confirmRemove(_ job: JobStatus) {
        let alert = NSAlert()
        alert.messageText = Format.removeJobTitle(job)
        alert.informativeText = Format.removeJobMessage(job)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        do {
            try client.removeJob(name: job.name)
            model.jobsBanner = Format.removedJobBanner(job)
            model.jobsBannerFailed = false
        } catch {
            model.jobsBanner = "Could not remove \(job.name): " + Format.error(error)
            model.jobsBannerFailed = true
        }
        reloadJobs()
    }

    func confirmDisconnect(_ app: MCPApp) {
        let alert = NSAlert()
        alert.messageText = "Disconnect \(app.name)?"
        alert.informativeText = Format.disconnectMessage(app)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Disconnect")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        setMCP(app, connected: false)
    }

    /// `jit mcp install` / `uninstall --client <app>`: one entry in the app's
    /// config, after a backup, and nothing else in it. Connecting approves
    /// nothing; it only lets the app's agent ask.
    func setMCP(_ app: MCPApp, connected: Bool) {
        let arguments = app.arguments(connected ? "install" : "uninstall")
        Task.detached {
            let result = JitCLI.execute(arguments)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                let text: String
                let failed: Bool
                switch result {
                case .success:
                    text = Format.mcpChangedBanner(app, connected: connected)
                    failed = false
                case let .failure(error):
                    text = "Could not \(connected ? "connect" : "disconnect") \(app.name): " + Self.describeTools(error)
                    failed = true
                }
                // Said in the window the button was pressed in.
                if agentsWindow.isVisible, !aiJobsWindow.isVisible {
                    model.agentsOutcome = WindowOutcome(title: text, text: text, failed: failed)
                } else {
                    model.jobsBanner = text
                    model.jobsBannerFailed = failed
                }
                reloadJobs()
            }
        }
    }
}
