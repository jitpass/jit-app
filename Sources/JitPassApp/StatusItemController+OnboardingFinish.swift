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
        onboarding.finishBusy = "recovery"
        Task.detached {
            let result = JitCLI.execute(["vault", "export", path, "--stdin"], stdin: passphrase)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                onboarding.finishBusy = nil
                switch result {
                case .success: onboarding.recoverySaved = path
                case let .failure(error): onboarding.finishProblems = ["Recovery file: " + Self.describeTools(error)]
                }
            }
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
        if let button = item.button, !panel.isVisible {
            panel.toggle(under: button)
        }
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
}
