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
            scanNow: { [weak self] in
                self?.openScan()
                self?.askDepth(scope: nil)
            },
            openVault: { [weak self] in self?.openVault() },
            openSettings: { [weak self] in self?.openSettings() },
            openInTerminal: { [weak self] in self?.runInTerminal("jit wrap list") }
        )
    }

    func openTools() {
        panel.dismiss()
        reloadTools()
        toolsWindow.present()
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
        runTools(path, work: { JitCLI.migrate([path]).map { [$0] } }, then: { [weak self] reports in
            guard let self else {
                return
            }
            model.scanStale = true
            let outcome = Self.protectOutcome(reports, wrapped: [], wraps: [])
            showResult(title: outcome.title, text: outcome.text, failed: outcome.failed, undo: outcome.undo)
            runScan(wholeMac: true, kind: .afterProtect)
        })
    }

    /// The result goes to whichever window is in front. Findings and AI
    /// Agents have a banner region, so there it is a sentence in the
    /// window with jit's own words one click away, and not a modal on top
    /// of the state it just changed.
    func showResult(title: String, text: String, failed: Bool = false, undo: [String] = []) {
        let outcome = WindowOutcome(title: title, text: text, failed: failed, undo: undo)
        if scanWindow.isKeyWindow {
            model.findingsOutcome = outcome
        } else if decoysWindow.isKeyWindow {
            model.decoysOutcome = outcome
        } else if agentsWindow.isKeyWindow || (agentsWindow.isVisible && !toolsWindow.isVisible) {
            model.agentsOutcome = outcome
        } else {
            model.toolsSheet = ToolsSheet.result(title: title, text: text)
        }
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

    /// `jit wrap <tool>`, after the sheet said what it does. With a value,
    /// `jit vault set <path> --stdin` runs first: the CLI cannot take the
    /// key in the same step, and that one field is the reason wrapping is
    /// in-app at all. Two Touch IDs then, and the sheet said so.
    func wrapTool(_ tool: String, value: String?) {
        let record = model.toolListing?.tool(named: tool)
        if value == nil, let key = record?.shellConfigKey(scan: model.macScan) {
            wrapFromShellConfig(tool, key: key)
            return
        }
        let path = record?.injects.first?.vaultPath
        let work: @Sendable () -> Result<String, Error> = {
            var log: [String] = []
            if let value, !value.isEmpty, let path {
                switch JitCLI.execute(["vault", "set", path, "--stdin", "--yes"], stdin: value) {
                case let .success(text): log.append(text)
                case let .failure(error): return .failure(error)
                }
            }
            return JitCLI.execute(["wrap", tool]).map { (log + [$0]).joined(separator: "\n\n") }
        }
        runTools(tool, work: work, then: { [weak self] output in
            self?.model.scanStale = true
            self?.model.toolsSheet = nil
            self?.model.agentsSheet = nil
            self?.showResult(title: "Wrapped \(tool)", text: output)
        })
    }

    /// A tool outside the catalog: `jit vault set wrap-<tool>/VAR --stdin`
    /// with the key from the sheet, then `jit wrap add <tool> --env
    /// VAR=wrap-<tool>/VAR`, the same shape `jit wrap` gives a catalog
    /// tool, so Unwrap and the listing treat it like one.
    private func handWrap(_ tool: String, name: String, value: String) {
        let path = "wrap-\(tool)/\(name)"
        let work: @Sendable () -> Result<String, Error> = {
            var log: [String] = []
            switch JitCLI.execute(["vault", "set", path, "--stdin", "--yes"], stdin: value) {
            case let .success(text): log.append(text)
            case let .failure(error): return .failure(error)
            }
            return JitCLI.execute(["wrap", "add", tool, "--env", name + "=" + path])
                .map { (log + [$0]).joined(separator: "\n\n") }
        }
        runTools(tool, work: work, then: { [weak self] output in
            self?.model.toolsSheet = nil
            self?.model.toolsSelected = tool
            self?.showResult(title: "Wrapped \(tool)", text: output)
        })
    }

    /// The key is an `export` in a shell config, which `jit wrap` does not
    /// read: `jit migrate <rc> --yes` moves it (the export line becomes a
    /// `jit export` of the same profile, so every shell keeps the var),
    /// then `jit wrap add <tool> --env VAR=<rc name>/VAR` points the shim
    /// at that copy. One Touch ID: the wrap only checks the path exists.
    private func wrapFromShellConfig(_ tool: String, key: ShellConfigKey) {
        let work: @Sendable () -> Result<String, Error> = {
            var log: [String] = []
            switch JitCLI.execute(["migrate", key.file, "--yes"]) {
            case let .success(text): log.append(text)
            case let .failure(error): return .failure(error)
            }
            return JitCLI.execute(["wrap", "add", tool, "--env", key.name + "=" + key.vaultPath])
                .map { (log + [$0]).joined(separator: "\n\n") }
        }
        runTools(tool, work: work, then: { [weak self] output in
            self?.model.scanStale = true
            self?.model.toolsSheet = nil
            self?.model.agentsSheet = nil
            self?.showResult(title: "Protected \(Format.home(key.file)), wrapped \(tool)", text: output)
            self?.runScan(wholeMac: true, kind: .afterProtect)
        })
    }

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
        runTools("caches", refresh: false, work: { JitCLI.execute(["migrate", "caches", "--yes"]) }, then: { [weak self] output in
            self?.model.scanStale = true
            self?.showResult(title: "Cleaned AI agent caches", text: output)
            self?.runScan(wholeMac: true, kind: .afterProtect)
        })
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
    func runTools<Output: Sendable>(
        _ label: String,
        refresh: Bool = true,
        work: @escaping @Sendable () -> Result<Output, Error>,
        then: @escaping @MainActor (Output) -> Void
    ) {
        guard model.toolsBusy == nil else {
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
                switch result {
                case let .success(output):
                    then(output)
                    if refresh {
                        reloadTools()
                        JitCLI.forgetStatus()
                        model.cli = JitCLI.status()
                    }
                case let .failure(error):
                    model.toolsMessage = Self.describeTools(error)
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
