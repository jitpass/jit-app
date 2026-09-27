// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The Tools window (docs/design/tools-window.md); the AI Agents window
/// is wired in `StatusItemController+Agents.swift` and sends the same
/// commands.
/// The listing is `jit wrap list --all`, prompt-free. Every change is a jit
/// command run from here after a sheet or dialog that says what runs, with
/// `--yes` only where that dialog asked the CLI's own question; the CLI's
/// output comes back verbatim, because the CLI is the one that says what it
/// found and moved: in a result sheet here, and in the AI Agents window's
/// banner, one click from the sentence. The app never touches the manifest,
/// the shims or an rc file itself. Minting a session stays in the terminal:
/// it is the IdP's MFA prompt, not jit's.
extension StatusItemController {
    var toolsActions: ToolsActions {
        ToolsActions(
            reload: { [weak self] in self?.reloadTools() },
            openSheet: { [weak self] sheet in
                self?.model.toolsMessage = nil
                self?.model.toolsSheet = sheet
            },
            closeSheet: { [weak self] in self?.model.toolsSheet = nil },
            wrap: { [weak self] tool, value in self?.wrapTool(tool, value: value) },
            handWrap: { [weak self] tool, name, value in self?.handWrap(tool, name: name, value: value) },
            protect: { [weak self] tool in self?.protectTool(tool) },
            protectFile: { [weak self] path in self?.protectFile(path) },
            unwrap: { [weak self] tool in self?.unwrapTool(tool) },
            verify: { [weak self] tool in self?.verifyTool(tool) },
            mintInTerminal: { [weak self] command in self?.runInTerminal(command) },
            cleanCaches: { [weak self] in self?.cleanCaches() },
            openVault: { [weak self] in self?.openVault() },
            openSettings: { [weak self] in self?.openSettings() },
            openScan: { [weak self] in self?.openScan() },
            openDoctor: { [weak self] in self?.openDoctor() },
            openAIJobs: { [weak self] in self?.openAIJobs() }
        )
    }

    func openTools() {
        panel.dismiss()
        reloadTools()
        refreshToolActivity()
        toolsWindow.present()
    }

    /// `jit audit --since 7d`, prompt-free, off the main thread: each
    /// wrapped tool's reads, for its row's fact. The listing may still be
    /// loading; the tools are read again when the audit lands.
    func refreshToolActivity() {
        let filter = AuditFilter(since: "7d", limit: 0)
        Task.detached {
            let report = JitCLI.audit(filter)
            await MainActor.run { [weak self] in
                guard let self, let report else {
                    return
                }
                var activity: [String: ToolActivity] = [:]
                for tool in model.toolListing?.others ?? [] where tool.wrapped || tool.isProtected {
                    activity[tool.tool] = report.toolActivity(vaultPaths: tool.injects.compactMap(\.vaultPath))
                }
                model.toolActivity = activity
            }
        }
    }

    /// `jit migrate <file> --yes` for one MCP config, after a dialog: the
    /// env-block tokens move into the vault, the file is rewritten to
    /// point at them, and it is backed up encrypted first.
    func protectFile(_ path: String) {
        // The same sweep sentence the Findings window's Protect carries:
        // migrate will also remove the cached copies of this file's secrets
        // the last whole-Mac scan found, and says so before Touch ID.
        let copies = model.macScan?.copies(from: [path]) ?? []
        let sweep = ScanWording.sweepSentence(copies: copies).map { " " + $0 } ?? ""
        let alert = NSAlert()
        alert.messageText = "Protect \(Format.home(path))?"
        alert.informativeText = "The credentials move into the vault; the file keeps working through jit." + sweep
            + "\n\nA backup restores it. Touch ID follows."
        alert.addButton(withTitle: "Protect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        model.findingsOutcome = nil
        runTools(path, failed: "Protect", work: { JitCLI.migrate([path]).map { [$0] } }, then: { [weak self] reports in
            guard let self else {
                return
            }
            model.scanStale = true
            let outcome = Self.protectOutcome(ProtectRun(reports: reports))
            showResult(title: outcome.title, text: outcome.text, failed: outcome.failed, undo: outcome.undo, changes: outcome.changes)
            vaultChanged()
            runScan(wholeMac: true, kind: .afterProtect)
        })
    }

    // The `status` poll may run while a reload is in flight; the reload's
    // own status read wins, so nothing is lost.

    /// Prompt-free, so it runs on every open and after every change. Off
    /// the main thread: with --discover the listing runs each unwrapped
    /// tool's export command, which is a second or two, and the window
    /// must not freeze for it. Status is re-read with it so the session
    /// rows are as fresh as the tool rows.
    func reloadTools() {
        guard !model.toolsRefreshing else {
            return
        }
        model.toolsRefreshing = true
        Task.detached {
            let result = Result { try JitCLI.toolList() }
            JitCLI.forgetStatus()
            let status = JitCLI.status()
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.toolsRefreshing = false
                model.cli = status
                switch result {
                case let .success(listing):
                    model.toolListing = listing
                    model.toolsMessage = nil
                    toolsReadAt = Date()
                case let .failure(error):
                    model.toolsMessage = Format.error(error)
                }
            }
        }
    }

    /// The panel's two rows need the listing before the window ever opens;
    /// it is one prompt-free jit run, re-read at most every status TTL.
    func reloadToolsIfStale() {
        if let at = toolsReadAt, Date().timeIntervalSince(at) < JitCLI.statusCacheTTL {
            return
        }
        reloadTools()
    }

    // MARK: - Wrap, protect, unwrap

    /// A native tool: `jit migrate ~ --only <category> --yes`, the migration
    /// `jit wrap <tool>` delegates to, after a dialog that names what
    /// migrate does and that it backs up first. The home path is passed
    /// absolute: migrate takes a path, and jit's own delegation spells it
    /// "home", which migrate reads relative to the working directory.
    private func protectTool(_ tool: String) {
        guard let record = model.toolListing?.tool(named: tool), let category = record.nativeCategory else {
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let alert = NSAlert()
        alert.messageText = "Protect \(tool)?"
        alert.informativeText = "\(record.doc ?? "The credential") moves into the vault; \(tool) keeps working through jit's hook."
            + "\n\nA backup restores the file. Touch ID follows."
        alert.addButton(withTitle: "Protect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        runTools(tool, work: { JitCLI.execute(["migrate", home, "--only", category, "--yes"]) }, then: { [weak self] output in
            self?.model.scanStale = true
            self?.showResult(title: "Protected \(tool)", text: output)
            self?.vaultChanged()
        })
    }

    /// `jit wrap undo <tool>`: prompt-free; the dialog exists because the
    /// shim comes out at once and open shells notice on their next call.
    func unwrapTool(_ tool: String) {
        let alert = NSAlert()
        alert.messageText = "Unwrap \(tool)?"
        alert.informativeText = "The shim comes out; \(tool) runs without jit from its next call. The secret stays in the vault."
        alert.addButton(withTitle: "Unwrap")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        runTools(tool, work: { JitCLI.execute(["wrap", "undo", tool]) }, then: { [weak self] output in
            self?.model.scanStale = true
            self?.showResult(title: "Unwrapped \(tool)", text: output)
        })
    }

    /// The catalog's verify hint, run under the app's PATH with its output
    /// in a sheet. A hint with a placeholder (`clisso get <app>`) cannot run
    /// unattended and goes to the terminal instead.
    private func verifyTool(_ tool: String) {
        guard let hint = model.toolListing?.tool(named: tool)?.verifyHint else {
            return
        }
        if hint.contains("<") {
            runInTerminal(hint)
            return
        }
        runTools(tool, refresh: false, work: { JitCLI.shell(hint) }, then: { [weak self] output in
            self?.showResult(title: hint, text: output.isEmpty ? "(no output, exit 0)" : output)
        })
    }

    /// `jit migrate caches --yes`: its plan needs the vault open, so there
    /// is no gesture-free preview; the dialog uses the scan's own count and
    /// says the CLI backs up every file it rewrites.
    func cleanCaches() {
        let copies = model.macScan?.agentCopies.count ?? 0
        let alert = NSAlert()
        alert.messageText = "Clean AI agent caches?"
        alert.informativeText = "Copies of your vaulted secrets in every AI agent's cache"
            + (copies > 0 ? " (the last scan found \(copies))" : "") + " become markers."
            + "\n\nFiles are backed up first; one an agent is writing is left alone. Touch ID follows."
        alert.addButton(withTitle: "Clean")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        model.findingsOutcome = nil
        runTools(
            "caches",
            refresh: false,
            failed: "Clean Caches",
            work: { JitCLI.execute(["migrate", "caches", "--yes"]) },
            then: { [weak self] output in
                self?.model.scanStale = true
                self?.showResult(title: "Cleaned AI agent caches", text: output)
                self?.runScan(wholeMac: true, kind: .afterProtect)
            }
        )
    }

    // MARK: - Guard

    /// `jit guard history` / `--remove`: prompt-free and instant, no
    /// service restart. Status is re-read afterwards so the toggle shows
    /// jit's verdict, never the app's assumption.
    func setGuard(_ on: Bool) {
        guard model.settingsApplying == nil else {
            return
        }
        model.settingsApplying = .history
        model.settingsOutcome = nil
        let arguments = ["guard", "history"] + (on ? [] : ["--remove"])
        Task.detached {
            let result = JitCLI.execute(arguments)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.settingsApplying = nil
                switch result {
                case .success:
                    model.settingsOutcome = .applied(.history, value: on ? "is on" : "is off")
                case let .failure(JitCLI.CLIError.failed(line)):
                    model.settingsOutcome = .failed(.history, line: line)
                case .failure:
                    model.settingsOutcome = .failed(.history, line: "jit is not installed where the app can find it.")
                }
                JitCLI.forgetStatus()
                model.cli = JitCLI.status()
            }
        }
    }

    // MARK: - Plumbing

    /// Runs one command off the main thread while the row shows who is
    /// waiting on Touch ID, then reloads the listing and status. One at a
    /// time, like the Vault window.
    ///
    /// `failed` names the action, so a failure reaches the window that
    /// asked (`showFailure`), recorded here, at the click; without it the
    /// line only goes to `toolsMessage`, which Findings and Decoys never
    /// show. `reportsTo` overrides the window for a run no click started.
    func runTools<Output: Sendable>(
        _ label: String,
        refresh: Bool = true,
        failed verb: String? = nil,
        reportsTo: OutcomeWindow? = nil,
        work: @escaping @Sendable () -> Result<Output, Error>,
        then: @escaping @MainActor (Output) -> Void
    ) {
        guard model.toolsBusy == nil else {
            return
        }
        model.toolsBusy = label
        let origin = reportsTo ?? frontOutcomeWindow
        model.toolsMessage = nil
        Task.detached {
            let result = work()
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.toolsBusy = nil
                switch result {
                case let .success(output):
                    then(output)
                    if refresh {
                        reloadTools()
                        JitCLI.forgetStatus()
                        model.cli = JitCLI.status()
                    }
                case let .failure(error):
                    let line = Self.describeTools(error)
                    model.toolsMessage = line
                    if let verb {
                        showFailure(verb, line: line, in: origin)
                    }
                }
            }
        }
    }

    nonisolated static func describeTools(_ error: Error) -> String {
        if case let JitCLI.CLIError.failed(line) = error {
            return line.isEmpty ? "jit did not say why" : line
        }
        if case JitCLI.CLIError.notInstalled = error {
            return "jit is not installed"
        }
        return Format.error(error)
    }
}
