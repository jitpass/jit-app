// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient
import ServiceManagement

/// The setup window's last screen: the recovery file, the switches Done
/// applies, and Undo. Each is something Settings or the Vault window
/// already does; this only asks at the moment it matters.
extension StatusItemController {
    /// What the finish screen offers depends on this Mac: the guard is a
    /// zsh hook, and the PATH link is for a copy Homebrew did not install.
    func onboardingPrepareFinish() {
        onboarding.migratedFiles = onboarding.tasks.first { $0.kind == .migrate && $0.state == .done }
            .flatMap(\.command).map { $0.filter { $0.hasPrefix("/") } } ?? []
        onboarding.offersGuard = (ProcessInfo.processInfo.environment["SHELL"] ?? "").hasSuffix("zsh")
            && model.cli?.guardStatus?.installed != true
        onboarding.offersCLI = model.cliTool == .missing && !CommandLineTool.installedByHomebrew()
        onboarding.launchAtLogin = true
        onboarding.finishProblems = []
        onboarding.finishApplied = false
    }

    /// Save panel, a passphrase typed twice, `jit vault export --stdin`:
    /// the Vault window's export, with the outcome on the row.
    func onboardingSaveRecovery() {
        saveRecoveryFile(
            started: { [weak self] in self?.onboarding.finishBusy = "recovery" },
            finished: { [weak self] result in
                guard let self else {
                    return
                }
                onboarding.finishBusy = nil
                switch result {
                case let .success(path): onboarding.recoverySaved = path
                case let .failure(error): onboarding.finishProblems = ["Recovery file: " + Self.describeTools(error)]
                }
            }
        )
    }

    /// The recovery file, for setup's finish screen and for Remove JitPass:
    /// `started` fires once the user has chosen a place and a passphrase,
    /// `finished` hears the saved path. Neither fires on a Cancel.
    func saveRecoveryFile(started: @escaping () -> Void, finished: @escaping (Result<String, Error>) -> Void) {
        let save = NSSavePanel()
        save.title = "Save a recovery file"
        save.message = "Somewhere that is not only this Mac is best: a drive, or a folder that syncs."
        save.nameFieldStringValue = "jitpass-recovery-\(Format.dateStamp()).export"
        save.canCreateDirectories = true
        guard save.runModal() == .OK, let url = save.url else {
            return
        }
        guard let passphrase = DoctorDialogs.askPassphrase(
            "Choose a passphrase for the recovery file. Without it the file cannot be opened, and nobody can reset it.",
            title: "Save"
        ) else {
            return
        }
        let path = url.path
        started()
        Task.detached {
            let result = JitCLI.execute(["vault", "export", path, "--stdin"], stdin: passphrase).map { _ in path }
            await MainActor.run { finished(result) }
        }
    }

    /// Applies the switches, then closes. Anything that did not apply is
    /// said on the screen and the button becomes Close: a login item that
    /// will not register must not trap the user in setup.
    func onboardingDone() {
        // "Done" on the results screen, with nothing to protect, never
        // showed the switches, so there is nothing of the user's to apply.
        guard onboarding.step == .done, !onboarding.finishApplied else {
            onboardingClose()
            return
        }
        onboarding.finishApplied = true
        var problems: [String] = []
        if onboarding.launchAtLogin, SMAppService.mainApp.status != .enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                problems.append("Open at login: \(error.localizedDescription)")
            }
        }
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        UserDefaults.standard.set(onboarding.notify, forKey: Notifier.decoyPreferenceKey)
        UserDefaults.standard.set(onboarding.notify, forKey: Notifier.changesPreferenceKey)
        model.notifyDecoys = onboarding.notify
        model.notifyChanges = onboarding.notify
        if onboarding.notify {
            Notifier.requestPermission()
        }
        if onboarding.offersGuard, onboarding.historyGuard {
            setGuard(true)
        }
        if onboarding.offersCLI, onboarding.installCLI {
            installCommandLineTool()
        }
        onboarding.finishProblems = problems
        if problems.isEmpty {
            onboardingClose()
        }
    }

    /// After setup: the full panel, shown once so the user sees where
    /// JitPass lives.
    private func onboardingClose() {
        onboardingWindow.close()
        resync()
        guard let button = item.button, statusItemOnScreen else {
            // On a notched display a full menu bar silently drops the items
            // that do not fit, so "it lives up here" would point at nothing.
            let alert = NSAlert()
            alert.messageText = "JitPass is hidden in your menu bar"
            alert.informativeText = "The menu bar is full, so macOS is not showing the JitPass ring. JitPass is running and "
                + "protecting you. To reach it, open JitPass again from Applications, or quit a menu bar app to make room."
            alert.runModal()
            return
        }
        if !panel.isVisible {
            panel.toggle(under: button)
        }
    }

    /// Best effort, and deliberately the narrow test: macOS parks a status
    /// item it has no room for off every screen. The window's occlusion
    /// state would catch more, but it also reads "not visible" for reasons
    /// that have nothing to do with the notch, and a false "JitPass is
    /// hidden" is worse than a missed one.
    private var statusItemOnScreen: Bool {
        guard let window = item.button?.window else {
            return false
        }
        return NSScreen.screens.contains { $0.frame.intersects(window.frame) }
    }

    /// Restores the files this setup rewrote, byte for byte, with jit's own
    /// `migrate undo`. The vault and its secrets stay, as the CLI's undo
    /// leaves them, and so do wrapped tools: the dialog says both.
    func onboardingUndo() {
        let files = onboarding.migratedFiles
        guard !files.isEmpty else {
            return
        }
        let alert = NSAlert()
        alert.messageText = files.count == 1 ? "Put 1 file back as it was?" : "Put \(files.count) files back as they were?"
        alert.informativeText = "This runs jit migrate undo: each file gets its original bytes back, plaintext secrets included. "
            + "The vault keeps its copies, and tools that were wrapped stay wrapped. Touch ID follows."
        alert.addButton(withTitle: "Undo")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        onboarding.finishBusy = "undo"
        Task.detached {
            let result = JitCLI.execute(["migrate", "undo"] + files + ["--yes"])
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                onboarding.finishBusy = nil
                switch result {
                case .success:
                    onboarding.migratedFiles = []
                    onboarding.tasks = []
                    model.scanStale = true
                    onboardingRescanAfterUndo()
                case let .failure(error):
                    onboarding.finishProblems = ["Undo: " + Self.describeTools(error)]
                }
            }
        }
    }

    // MARK: - Restore

    func onboardingShowRestore() {
        onboarding.restoreError = nil
        onboarding.strandedSecrets = model.setup == .needsRestore ? (model.cli?.vault?.secretsStored ?? 0) : 0
        onboarding.step = .restore
    }

    func onboardingChooseRestoreFile() {
        let open = NSOpenPanel()
        open.title = "Choose a recovery file"
        open.canChooseDirectories = false
        open.allowsMultipleSelection = false
        guard open.runModal() == .OK, let url = open.url else {
            return
        }
        onboarding.restoreFile = url.path
    }

    /// `jit vault init` when this Mac has no key (it never replaces one),
    /// then `jit vault import <file> --stdin --yes`. The passphrase leaves
    /// the model the moment the command has it.
    func onboardingRestore() {
        guard let file = onboarding.restoreFile, !onboarding.restorePassphrase.isEmpty else {
            return
        }
        let passphrase = onboarding.restorePassphrase
        let needsKey = model.setup != .ready
        onboarding.restoreBusy = true
        onboarding.restoreError = nil
        Task.detached {
            var result: Result<String, Error> = needsKey ? JitCLI.execute(["vault", "init"]) : .success("")
            if case .success = result {
                result = JitCLI.execute(["vault", "import", file, "--stdin", "--yes"], stdin: passphrase)
            }
            let outcome = result
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                onboarding.restoreBusy = false
                onboarding.restorePassphrase = ""
                switch outcome {
                case .success:
                    JitCLI.forgetStatus()
                    model.cli = JitCLI.status()
                    render()
                    onboardingRescanAfterUndo()
                case let .failure(error):
                    onboarding.restoreError = Self.describeTools(error)
                }
            }
        }
    }
}
