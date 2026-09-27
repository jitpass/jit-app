// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The Protect verb's shared pieces: the work off the main thread, the
/// banner's sentence from the reports' fields, and the Undo the banner
/// offers. Used by the Findings window's Protect (StatusItemController+Scan)
/// and the AI Agents window's Protect on an MCP config
/// (StatusItemController+Tools).
extension StatusItemController {
    /// Runs the plan: the vault first when this Mac has none, then one
    /// `jit migrate <files> --yes --format json`, then each `jit wrap`.
    /// A migrate that failed still returns its document with the partial
    /// result, which is what the banner must show; so does a wrap that
    /// failed once something had changed (`ProtectRun.changedSomething`),
    /// with jit's line recorded and the wraps after it not tried.
    nonisolated static func protectWork(
        createsVault: Bool, migrate: [String], flags: [String] = [], wraps: [String]
    ) -> Result<ProtectRun, Error> {
        if createsVault, case let .failure(error) = JitCLI.execute(["vault", "init"]) {
            return .failure(error)
        }
        var run = ProtectRun()
        if !migrate.isEmpty {
            switch JitCLI.migrate(migrate, flags: flags) {
            case let .success(report): run.reports.append(report)
            case let .failure(error): return .failure(error)
            }
        }
        for (index, tool) in wraps.enumerated() {
            switch JitCLI.execute(["wrap", tool]) {
            case let .success(text):
                run.wrapped.append(tool)
                run.wrappedText.append(text)
            case let .failure(error):
                guard run.changedSomething else {
                    return .failure(error)
                }
                run.wrapFailure = ProtectRun.WrapFailure(tool: tool, line: describeTools(error), notTried: Array(wraps[(index + 1)...]))
                return .success(run)
            }
        }
        return .success(run)
    }

    /// The banner's sentence and jit's words, from the run's fields
    /// (`ProtectRun.outcome`). Undo carries the files a migrate applied to.
    static func protectOutcome(_ run: ProtectRun) -> WindowOutcome {
        let outcome = run.outcome(home: FileManager.default.homeDirectoryForCurrentUser.path)
        return WindowOutcome(title: outcome.title, text: outcome.text, failed: outcome.failed, undo: outcome.undo, changes: outcome.changes)
    }

    /// Redact… on a row, Redact All… on a sheet or the card: the tokens the
    /// scan found by format in agent caches become `<jit:redacted:VENDOR>`
    /// markers. No vault, no backup, no Touch ID (jit's D12), and the dialog
    /// says the change is one-way. `files` empty is every cache; `lines`
    /// narrows to one row's line.
    func redact(files: [String], lines: [Int], what: String, place: String?) {
        // A question, not a paragraph: the file's name and where it sits on
        // one line, then what happens and what it costs, one sentence each.
        let alert = NSAlert()
        alert.messageText = "Redact \(what)?"
        let location = files.count == 1
            ? Format.fileName(files[0]) + (place.map { " · " + $0 } ?? "")
            : "AI agent caches only, never your files"
        let plural = files.count != 1 || lines.isEmpty
        alert.informativeText = location + "\n\n"
            +
            (plural ? "Each token becomes a marker; the lines otherwise stay. " :
                "The token becomes a marker; the rest of the line stays. ")
            + "This can't be undone."
        alert.addButton(withTitle: "Redact")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        model.findingsOutcome = nil
        runTools(
            "redact",
            refresh: false,
            failed: "Redact",
            work: { JitCLI.redact(files: files, lines: lines) },
            then: { [weak self] report in
                guard let self else {
                    return
                }
                let outcome = ScanWording.redactOutcome(report)
                showResult(title: outcome.title, text: report.report, failed: outcome.failed, changes: .redact(report))
                settle(after: report, lines: lines)
            }
        )
    }

    /// A Redact changed exactly the files its report names, so the report on
    /// screen is updated from it — those rows go — instead of reading the
    /// whole Mac again for a few lines. The next scheduled scan confirms;
    /// `scanStale` asks for it sooner.
    func settle(after report: RedactReport, lines: [Int]) {
        let paths = report.caches.removed.map(\.path)
        guard !paths.isEmpty else {
            return
        }
        model.scan = model.scan?.removingCacheShapes(in: paths, lines: lines)
        model.macScan = model.macScan?.removingCacheShapes(in: paths, lines: lines)
        model.scanStale = true
        if let report = model.macScan, let at = model.macScanAt, let kind = model.macScanKind {
            LastScanStore.save(LastScan(report: report, at: at, kind: kind, deepAt: model.macDeepScanAt))
        }
    }

    /// After a scheduled scan, under the Settings switch: the same command,
    /// no dialog, its result said once in a notification and in the
    /// Findings banner. Agent caches only, and nothing here ever prompts —
    /// the command needs no vault.
    func autoRedact(after report: ScanReport, at: Date) {
        guard !report.cacheShapes.isEmpty, model.toolsBusy == nil else {
            return
        }
        // Every cache under the global switch; otherwise only the files of
        // the agents whose own switch is on (AI Agents), and nothing when
        // none is.
        var files: [String] = []
        if !model.redactAfterScan {
            let labels = (model.toolListing?.agents ?? []).filter { model.redactAgents.contains($0.tool) }.compactMap(\.agentLabel)
            files = labels.flatMap { report.agentExposure($0).tokenPaths }
            guard !files.isEmpty else {
                return
            }
        }
        runTools(
            "redact",
            refresh: false,
            failed: "Redact after the scheduled scan",
            reportsTo: .findings,
            work: { JitCLI.redact(files: files, lines: []) },
            then: { [weak self] result in
                guard let self else {
                    return
                }
                let outcome = ScanWording.redactOutcome(result)
                model.findingsOutcome = WindowOutcome(
                    title: outcome.title, text: result.report, failed: outcome.failed, changes: .redact(result)
                )
                if model.notifyScans, let notice = ScanNotices.redacted(result, at: at) {
                    Notifier.post(
                        title: notice.title,
                        body: notice.body,
                        id: "redact-\(Int(at.timeIntervalSince1970))",
                        thread: "findings",
                        target: .findings
                    )
                }
                settle(after: result, lines: [])
            }
        )
    }

    /// `jit migrate undo <file> --yes` from the Findings banner: the file
    /// comes back from its encrypted backup, so its secret is plaintext on
    /// disk again — said before Touch ID. The cache copies the Protect
    /// removed stay removed; they have their own undo, named in jit's
    /// words.
    func undoProtect(_ paths: [String]) {
        guard !paths.isEmpty else {
            return
        }
        let alert = NSAlert()
        alert.messageText = paths.count == 1 ? "Undo protecting \(Format.home(paths[0]))?" : "Undo protecting \(paths.count) files?"
        alert.informativeText = (paths.count == 1 ? "The file is" : "Each file is")
            + " restored from its encrypted backup, so the secret is plaintext on disk again. "
            + "The cached copies the Protect removed stay removed. Touch ID follows."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        model.findingsOutcome = nil
        let title = paths.count == 1 ? "Restored \(Format.home(paths[0]))" : "Restored \(paths.count) files"
        runTools("undo", failed: "Undo", work: { JitCLI.execute(["migrate", "undo"] + paths + ["--yes"]) }, then: { [weak self] output in
            self?.model.scanStale = true
            self?.showResult(title: title, text: output)
            self?.vaultChanged()
            self?.runScan(wholeMac: true, kind: .afterProtect)
        })
    }
}
