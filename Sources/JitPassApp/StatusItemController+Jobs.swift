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
            newJob: { [weak self] in self?.openJobSheet() },
            review: { [weak self] proposal in self?.openProposal(proposal) },
            reviewJob: { [weak self] job in self?.openJobReview(job) },
            connect: { [weak self] in self?.setClaudeDesktop(connected: true) },
            disconnect: { [weak self] in self?.confirmDisconnect() },
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
        model.claudeDesktopInstalled = FileManager.default.fileExists(atPath: "/Applications/Claude.app")
        Task.detached {
            let jobs = (try? client.jobs()) ?? []
            let proposals = (try? client.jobProposals()) ?? []
            let mcp = try? JitCLI.document(["mcp", "status", "--format", "json"]) {
                try JSONDecoder().decode(MCPStatus.self, from: Data($0.utf8))
            }.get()
            await MainActor.run { [weak self] in
                self?.model.jobs = jobs
                self?.model.jobProposals = proposals
                self?.model.claudeDesktopMCP = mcp
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

    func confirmDisconnect() {
        let alert = NSAlert()
        alert.messageText = "Disconnect Claude Desktop?"
        alert.informativeText = "Cowork can no longer list or run your AI jobs. Your jobs stay; connecting again brings them back."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Disconnect")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        setClaudeDesktop(connected: false)
    }

    /// `jit mcp install` / `uninstall`: one entry in Claude Desktop's config,
    /// after a backup, and nothing else in it. Connecting approves nothing.
    func setClaudeDesktop(connected: Bool) {
        let arguments = ["mcp", connected ? "install" : "uninstall"]
        Task.detached {
            let result = JitCLI.execute(arguments)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                switch result {
                case .success:
                    model.jobsBanner = connected ? Format.connectedBanner : Format.disconnectedBanner
                    model.jobsBannerFailed = false
                case let .failure(error):
                    let verb = connected ? "connect" : "disconnect"
                    model.jobsBanner = "Could not \(verb) Claude Desktop: " + Self.describeTools(error)
                    model.jobsBannerFailed = true
                }
                reloadJobs()
            }
        }
    }
}
