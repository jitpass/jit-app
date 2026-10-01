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
            reveal: { path in Editor.reveal(path) },
            copyPath: { path in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            },
            undoProtect: { [weak self] paths in self?.undoProtect(paths) },
            protectAgain: { [weak self] paths in self?.protectFiles(paths) },
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
        protectFiles([path])
    }

    /// `jit migrate <files> --yes`, after the same dialog: one file from a
    /// grant tool's row, or every file an undo restored (Protect Again).
    func protectFiles(_ paths: [String]) {
        guard !paths.isEmpty else {
            return
        }
        // The same sweep sentence the Findings window's Protect carries:
        // migrate will also remove the cached copies of these files' secrets
        // the last whole-Mac scan found, and says so before Touch ID.
        let copies = model.macScan?.copies(from: paths) ?? []
        let sweep = ScanWording.sweepSentence(copies: copies).map { " " + $0 } ?? ""
        let alert = NSAlert()
        alert.messageText = paths.count == 1 ? "Protect \(Format.home(paths[0]))?" : "Protect \(paths.count) files?"
        alert.informativeText = "The credentials move into the vault; "
            + (paths.count == 1 ? "the file keeps" : "each file keeps") + " working through jit." + sweep
            + "\n\nA backup restores " + (paths.count == 1 ? "it" : "each one") + ". Touch ID follows."
        alert.addButton(withTitle: "Protect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        model.findingsOutcome = nil
        runTools(paths[0], failed: "Protect", work: { JitCLI.migrate(paths).map { [$0] } }, then: { [weak self] reports in
            guard let self else {
                return
            }
            model.scanStale = true
            settle(after: ProtectRun(reports: reports))
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

    /// A native tool: `jit wrap <tool> --yes --format json`, after a dialog
    /// that names what it does and that it backs up first. jit names the
    /// tool's own credential file (`~/.aws/credentials`); the app used to
    /// run `jit migrate ~ --only <category>`, which walks a folder for
    /// project files only and so found nothing to protect (jit #206). The
    /// result is the What Changed rows of the migration jit ran.
    private func protectTool(_ tool: String) {
        guard let record = model.toolListing?.tool(named: tool), record.nativeCategory != nil else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "Protect \(tool)?"
        alert.informativeText = "\(record.doc ?? "The credential") moves into the vault; \(tool) keeps working."
            + "\n\nA backup restores the file. Touch ID follows."
        alert.addButton(withTitle: "Protect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        runTools(tool, work: { JitCLI.wrap(tool, yes: true) }, then: { [weak self] report in
            self?.model.scanStale = true
            self?.showChanges(.wrapped(report))
            self?.vaultChanged()
        })
    }

    /// `jit wrap undo <tool>`: prompt-free; the dialog exists because the
    /// shim comes out at once and open shells notice on their next call.
    /// No result sheet: the dialog said what happens, and the row turning
    /// Not wrapped says it again. A failure keeps its one-line message.
    func unwrapTool(_ tool: String) {
        let alert = NSAlert()
        alert.messageText = "Unwrap \(tool)?"
        alert.informativeText = "\(tool) runs without jit from its next run. Its key stays in the vault."
        alert.addButton(withTitle: "Unwrap")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        runTools(tool, work: { JitCLI.execute(["wrap", "undo", tool]) }, then: { [weak self] _ in
            self?.model.scanStale = true
        })
    }

    /// The catalog's verify hint, run under the app's PATH: does the tool
    /// work with jit's key? The sheet answers that, and keeps the tool's
    /// words for a failure and a disclosure. A check that prints a secret
    /// (verify_prints_secret) runs with its output thrown away unread.
    /// gh's own JSON names its accounts, so they become rows. A hint with a
    /// placeholder (`clisso get <app>`) cannot run unattended and goes to
    /// the terminal instead.
    func verifyTool(_ tool: String) {
        guard let record = model.toolListing?.tool(named: tool), let hint = record.verifyHint else {
            return
        }
        if hint.contains("<") {
            runInTerminal(hint)
            return
        }
        let printsSecret = record.verifyPrintsSecret
        runTools(tool, refresh: false, work: {
            let plain = JitCLI.check(hint, keep: !printsSecret)
            var gh: GhAuthStatus?
            if tool == "gh", case let .success(json) = JitCLI.check((["gh"] + GhAuthStatus.arguments).joined(separator: " ")) {
                gh = try? GhAuthStatus.parse(Data(json.output.utf8))
            }
            return plain.map {
                ChangeSheet.verify(tool: tool, hint: hint, status: $0.status, output: $0.output, printsSecret: printsSecret, gh: gh)
            }
        }, then: { [weak self] sheet in
            self?.showChanges(sheet)
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
            + "\n\nEach file is backed up first. Touch ID follows."
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
            work: { JitCLI.migrateCaches() },
            then: { [weak self] report in
                self?.model.scanStale = true
                self?.showChanges(.caches(report))
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
                refreshCLI()
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
        let origin = reportsTo ?? frontOutcomeWindow
        guard model.toolsBusy == nil else {
            // Queued with the window it was asked from, never dropped: the
            // caller has already cleared its banner and asked its question.
            toolsQueue.append { [weak self] in
                self?.runTools(label, refresh: refresh, failed: verb, reportsTo: origin, work: work, then: then)
            }
            return
        }
        model.toolsBusy = label
        model.toolsMessage = nil
        Task.detached {
            let result = work()
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.toolsBusy = nil
                defer {
                    if !toolsQueue.isEmpty {
                        toolsQueue.removeFirst()()
                    }
                }
                switch result {
                case let .success(output):
                    outcomeWindowOverride = origin
                    then(output)
                    outcomeWindowOverride = nil
                    if refresh {
                        reloadTools()
                        refreshCLI()
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
