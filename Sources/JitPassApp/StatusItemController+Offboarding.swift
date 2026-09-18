// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient
import ServiceManagement
import UserNotifications

/// Remove JitPass (docs/design/offboarding.md). jit does everything jit
/// installed, under one fingerprint: `jit uninstall --restore`. The app then
/// removes only what the app itself put on this Mac. The end state is the
/// one a Mac that never had JitPass is in, so installing again opens setup
/// at Welcome.
extension StatusItemController {
    var offboardingActions: OffboardingActions {
        OffboardingActions(
            cancel: { [weak self] in self?.offboardingWindow.close() },
            next: { [weak self] in self?.offboarding.step = .recovery },
            back: { [weak self] in self?.offboarding.step = .plan },
            saveRecovery: { [weak self] in self?.offboardingSaveRecovery() },
            remove: { [weak self] in self?.offboardingRemove(restoring: self?.offboarding.restoring ?? true) },
            tryAgain: { [weak self] in self?.openOffboarding() },
            removeAnyway: { [weak self] in self?.offboardingRemoveAnyway() },
            show: { path in NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) },
            finish: { [weak self] in self?.offboardingFinish() }
        )
    }

    func makeOffboardingWindow() -> ReportWindow {
        let size = NSSize(width: OnboardingView.size.width, height: OnboardingView.size.height)
        let window = ReportWindow(
            title: "Remove JitPass",
            content: OffboardingView(model: offboarding, actions: offboardingActions),
            size: size,
            minSize: size
        )
        window.styleMask.remove([.resizable, .miniaturizable])
        window.mayClose = { [weak self] in self?.offboarding.removing != true }
        return window
    }

    /// Reads the plan and shows it. Nothing here changes anything: the plan
    /// is jit's dry run, which takes no fingerprint.
    func openOffboarding() {
        // The PATH-link test compares resolved bundle paths, and a
        // translocated copy resolves to a temporary one.
        if Translocation.isActive() {
            let alert = NSAlert()
            alert.messageText = "Move JitPass to Applications first"
            alert.informativeText = "macOS is running this copy from a temporary place, so it cannot tell which files are its own. "
                + "Move it to Applications, open it from there, and remove it from Settings."
            alert.runFrontmost()
            return
        }
        settingsWindow.close()
        offboarding.step = .loading
        offboarding.failures = []
        offboarding.problems = []
        offboarding.stopped = nil
        offboarding.recoveryError = nil
        offboarding.homebrew = CommandLineTool.installedByHomebrew()
        offboardingWindow.present()
        Task.detached {
            let result = JitCLI.uninstallPlan()
            await MainActor.run { [weak self] in
                guard let self, offboarding.step == .loading else {
                    return
                }
                switch result {
                case let .success(plan):
                    offboarding.plan = plan
                    offboarding.step = .plan
                case let .failure(error):
                    offboarding.step = .unavailable(Self.describeOffboarding(error))
                }
            }
        }
    }

    nonisolated static func describeOffboarding(_ error: Error) -> String {
        let why = describeTools(error)
        if why.contains("unknown flag") {
            return "This copy of jit is too old to put your files back. Update JitPass, then try again."
        }
        return why
    }

    private func offboardingSaveRecovery() {
        offboarding.recoveryError = nil
        saveRecoveryFile(
            started: { [weak self] in self?.offboarding.recoveryBusy = true },
            finished: { [weak self] result in
                guard let self else {
                    return
                }
                offboarding.recoveryBusy = false
                offboardingWindow.reclaimFocus()
                switch result {
                case let .success(path): offboarding.recoverySaved = path
                case let .failure(error): offboarding.recoveryError = Self.describeTools(error)
                }
            }
        )
    }

    /// The one path that deletes without restoring everything: said in
    /// full, and offered a recovery file first.
    private func offboardingRemoveAnyway() {
        let count = offboarding.failures.count
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = count == 1
            ? "Remove JitPass and leave 1 file as it is?"
            : "Remove JitPass and leave \(count) files as they are?"
        let recovery = offboarding.recoverySaved == nil
            ? "A recovery file keeps them: Cancel, then Try Again and save one first."
            : "Your recovery file still holds them."
        alert.informativeText = "Those files keep pointing at a vault that will no longer exist, "
            + "and their secrets are deleted with it. " + recovery
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Remove Anyway")
        guard alert.runFrontmost() == .alertSecondButtonReturn else {
            return
        }
        offboardingRemove(restoring: false)
    }

    private func offboardingRemove(restoring: Bool) {
        let command = restoring ? OffboardingPlan.restoreCommand : OffboardingPlan.purgeCommand
        offboarding.stopped = nil
        offboarding.failures = []
        offboarding.tasks = OffboardingPlan.tasks(plan: offboarding.plan, restoring: restoring)
        offboarding.step = .removing
        // Before jit stops the service: another jit on PATH is found by the
        // same lookup the PATH link uses, and named on Done.
        if case let .other(path)? = model.cliTool {
            offboarding.otherJit = path
        }
        Task.detached {
            let outcome = JitCLI.uninstall(command) { event in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    offboarding.tasks = OffboardingPlan.advance(offboarding.tasks, with: event)
                }
            }
            await MainActor.run { [weak self] in self?.offboardingEngineFinished(outcome) }
        }
    }

    private func offboardingEngineFinished(_ outcome: JitCLI.UninstallOutcome) {
        defer { offboardingWindow.reclaimFocus() }
        switch outcome {
        case let .couldNotRestore(failures):
            offboarding.failures = failures
            offboarding.step = .couldNotRestore
        case let .failed(why):
            offboarding.stopped = why + " Nothing was deleted."
        case let .removed(problems):
            offboarding.tasks = OffboardingPlan.advance(offboarding.tasks, with: .done(problems: problems))
            offboarding.tasks = OffboardingPlan.advance(offboarding.tasks, with: .step(OffboardingPlan.appStep))
            offboarding.problems = problems + removeAppFootprint()
            if let index = offboarding.tasks.firstIndex(where: { $0.id == OffboardingPlan.appStep }) {
                offboarding.tasks[index].state = .done
            }
            offboarding.step = .done
        }
    }

    /// What the app itself put on this Mac, and nothing else. Returns what
    /// did not come off, in words; none of it stops the rest.
    private func removeAppFootprint() -> [String] {
        var problems: [String] = []
        if SMAppService.mainApp.status == .enabled {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                problems.append("Open at login is still on: " + Format.error(error))
            }
        }
        // Homebrew's link is Homebrew's: `brew uninstall` takes it.
        if !offboarding.homebrew, case let .linked(link)? = model.cliTool, let problem = Self.removeLink(link) {
            problems.append(problem)
        }
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("jitpass"))
        Self.forgetPreferences()
        return problems
    }

    /// Everything macOS keeps under this bundle id. Run again at the very
    /// end: a timer that fires in between would write a preference back.
    private static func forgetPreferences() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.jitpass.app"
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        for leftover in [
            "Caches/\(bundleID)", "HTTPStorages/\(bundleID)", "HTTPStorages/\(bundleID).binarycookies",
            "Saved Application State/\(bundleID).savedState", "WebKit/\(bundleID)"
        ] {
            try? FileManager.default.removeItem(at: library.appendingPathComponent(leftover))
        }
    }

    /// Removes the PATH link this app made. A link in /usr/local/bin was
    /// made with an administrator password and needs one to come off.
    private static func removeLink(_ link: String) -> String? {
        if (try? FileManager.default.removeItem(atPath: link)) != nil {
            return nil
        }
        // The path, quoted for sh, then escaped for the AppleScript string
        // that carries it.
        let quoted = "'" + link.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let escaped = quoted.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"rm -f \(escaped)\" with administrator privileges"
        var failure: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&failure)
        return failure == nil ? nil : "The jit command is still at \(link). Remove it with: sudo rm \(link)"
    }

    /// The last click. A website install goes to the Trash; a Homebrew one
    /// is brew's to remove, along with the link and completions it owns.
    private func offboardingFinish() {
        // Full Disk Access and the notification permission. Last, because
        // losing them mid-run would change what the steps above could see.
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "All", Bundle.main.bundleIdentifier ?? "com.jitpass.app"]
        reset.standardOutput = FileHandle.nullDevice
        reset.standardError = FileHandle.nullDevice
        try? reset.run()
        reset.waitUntilExit()

        if offboarding.homebrew {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(OffboardingFinish.brewCommand, forType: .string)
        } else {
            NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in }
        }
        Self.forgetPreferences()
        // recycle is asynchronous; give it a moment before the process goes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            Self.forgetPreferences()
            NSApp.terminate(nil)
        }
    }
}
