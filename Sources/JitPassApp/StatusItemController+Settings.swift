// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient
import ServiceManagement

/// Settings and About.
extension StatusItemController {
    var settingsActions: SettingsActions {
        SettingsActions(
            addExclude: { [weak self] in self?.chooseExcludeFolder() },
            removeExclude: { [weak self] path in self?.model.scanExcludes = ScanExcludes.remove(path) },
            setTerminal: { [weak self] name in
                UserDefaults.standard.set(name, forKey: Terminal.preferenceKey)
                self?.model.terminalApp = name
            },
            setEditor: { [weak self] id in
                UserDefaults.standard.set(id, forKey: Editor.preferenceKey)
                self?.model.editorApp = id
            },
            setLaunchAtLogin: { [weak self] on in self?.setLaunchAtLogin(on) },
            setScanSchedule: { [weak self] schedule in
                UserDefaults.standard.set(schedule.rawValue, forKey: ScanSchedule.preferenceKey)
                self?.model.scanSchedule = schedule
                self?.refreshScanIfDue()
            },
            setRedactAfterScan: { [weak self] on in
                UserDefaults.standard.set(on, forKey: Notifier.redactAfterScanKey)
                self?.model.redactAfterScan = on
            },
            grantFullDiskAccess: { FullDiskAccess.openSettings() },
            setTTL: { [weak self] ttl, label in
                self?.applyService(["service", "ttl", ttl], row: .lockTimer, value: label)
            },
            setConsent: { [weak self] on in
                self?.applyService(["service", "consent", on ? "on" : "off"], row: .consent, value: on ? "is on" : "is off")
            },
            setGuard: { [weak self] on in self?.setGuard(on) },
            setNotifyDecoys: { [weak self] on in
                UserDefaults.standard.set(on, forKey: Notifier.decoyPreferenceKey)
                self?.model.notifyDecoys = on
                if on {
                    Notifier.requestPermission { self?.refreshNotificationPermission() }
                }
            },
            setNotifySessions: { [weak self] on in
                UserDefaults.standard.set(on, forKey: Notifier.sessionsPreferenceKey)
                self?.model.notifySessions = on
                if on {
                    Notifier.requestPermission { self?.refreshNotificationPermission() }
                }
            },
            setNotifyScans: { [weak self] on in
                UserDefaults.standard.set(on, forKey: Notifier.scansPreferenceKey)
                self?.model.notifyScans = on
                if on {
                    Notifier.requestPermission { self?.refreshNotificationPermission() }
                }
            },
            setNotifyJobs: { [weak self] on in
                UserDefaults.standard.set(on, forKey: Notifier.jobsPreferenceKey)
                self?.model.notifyJobs = on
                if on {
                    Notifier.requestPermission { self?.refreshNotificationPermission() }
                }
            },
            allowNotifications: { [weak self] in self?.allowNotifications() },
            openNotificationSettings: { Notifier.openSystemSettings() },
            moveVaultKey: { [weak self] in self?.openVaultKeyMove() },
            saveRecoveryFile: { [weak self] in self?.saveRecoveryFile() },
            confirmVaultKeyMove: { [weak self] in self?.confirmVaultKeyMove() },
            cancelVaultKeyMove: { [weak self] in self?.model.vaultKeySheet = false },
            moveVaultKeyBack: { [weak self] in self?.confirmMoveBack() },
            retryVaultKey: { [weak self] in self?.retryVaultKey() },
            checkVaultKeyAgain: { [weak self] in self?.checkVaultKeyAgain() },
            restoreVaultKey: { [weak self] in self?.restoreVaultKey() },
            vaultClean: { [weak self] in self?.vaultDestructive(
                "clean",
                does: "deletes every secret and every backup for good; the vault and its key stay"
            ) },
            vaultDelete: { [weak self] in
                self?.vaultDestructive("delete", does: "destroys the vault directory and its key")
            },
            setCheckForUpdates: { [weak self] on in self?.setCheckForUpdates(on) },
            checkForUpdates: { [weak self] in self?.checkForUpdates(manual: true) },
            installUpdate: { [weak self] in self?.installUpdate() },
            installCommandLineTool: { [weak self] in self?.installCommandLineTool() },
            removeJitPass: { [weak self] in self?.openOffboarding() },
            startService: { [weak self] in self?.startService() }
        )
    }

    /// The two commands the window never runs: they go to the terminal
    /// with jit's own y/N as the last word, after this dialog has said what
    /// they do.
    private func vaultDestructive(_ command: String, does: String) {
        let alert = NSAlert()
        alert.messageText = "jit vault \(command)?"
        alert.informativeText = "This opens the terminal and runs:\n\njit vault \(command)\n\n"
            + "It \(does). jit asks once more before it does."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open in Terminal")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        runInTerminal("jit vault \(command)")
    }

    private func chooseExcludeFolder() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = true
        picker.prompt = "Exclude"
        picker.message = "Choose folders every scan should skip."
        guard picker.runFrontmost() == .OK else {
            return
        }
        for url in picker.urls {
            model.scanExcludes = ScanExcludes.add(url.path)
        }
    }

    func openSettings() {
        panel.dismiss()
        model.terminalApp = UserDefaults.standard.string(forKey: Terminal.preferenceKey) ?? ""
        model.editors = Editor.installed()
        model.editorApp = Editor.chosen()?.bundleID ?? ""
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        model.fullDiskAccess = FullDiskAccess.granted()
        model.settingsOutcome = nil
        loadVaultKeyPreferences()
        refreshNotificationPermission()
        if model.cli == nil {
            model.cli = JitCLI.status()
        }
        // An enclave key is not shown healthy before doctor has said this
        // Mac has it: the row reads "checking" until the report lands.
        if model.vaultKeyRow == .checking || model.vaultKeyRow == .unchecked {
            refreshDoctorIfStale()
        }
        model.updateMessage = nil
        refreshCommandLineTool()
        settingsWindow.present()
    }

    func showAbout() {
        panel.dismiss()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    /// Login-item registration through the system's own service, which
    /// shows the app under System Settings › General › Login Items.
    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            model.launchAtLogin = SMAppService.mainApp.status == .enabled
            model.settingsOutcome = .applied(.launchAtLogin, value: on ? "is on" : "is off")
        } catch {
            model.settingsOutcome = .failed(.launchAtLogin, line: error.localizedDescription)
        }
    }

    /// One `jit service …` invocation, off the main thread: both restart
    /// the service, and consent-off waits on the CLI's own Touch ID prompt.
    /// The stream ends with the restart and reconnects on its own.
    private func applyService(_ arguments: [String], row: SettingsOutcome.Row, value: String) {
        guard model.settingsApplying == nil else {
            return
        }
        model.settingsApplying = row
        model.settingsOutcome = nil
        Task.detached {
            let result = JitCLI.apply(arguments)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.settingsApplying = nil
                switch result {
                case .success:
                    model.settingsOutcome = .applied(row, value: value)
                case let .failure(JitCLI.CLIError.failed(line)):
                    model.settingsOutcome = .failed(row, line: line)
                case .failure:
                    model.settingsOutcome = .failed(row, line: "jit is not installed where the app can find it.")
                }
                pollStatus()
                runDoctor()
            }
        }
    }
}
