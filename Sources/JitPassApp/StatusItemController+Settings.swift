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
            grantFullDiskAccess: { FullDiskAccess.openSettings() },
            setTTL: { [weak self] ttl in self?.applyService(["service", "ttl", ttl]) },
            setConsent: { [weak self] on in self?.applyService(["service", "consent", on ? "on" : "off"]) },
            setGuard: { [weak self] on in self?.setGuard(on) },
            setNotifyDecoys: { [weak self] on in
                UserDefaults.standard.set(on, forKey: Notifier.decoyPreferenceKey)
                self?.model.notifyDecoys = on
                if on {
                    Notifier.requestPermission()
                }
            },
            setNotifyChanges: { [weak self] on in
                UserDefaults.standard.set(on, forKey: Notifier.changesPreferenceKey)
                self?.model.notifyChanges = on
                if on {
                    Notifier.requestPermission()
                }
            },
            vaultClean: { [weak self] in self?.vaultDestructive(
                "clean",
                does: "deletes every secret and every backup for good; the vault and its key stay"
            ) },
            vaultDelete: { [weak self] in
                self?.vaultDestructive("delete", does: "destroys the vault directory and its key in the keychain")
            },
            setCheckForUpdates: { [weak self] on in self?.setCheckForUpdates(on) },
            checkForUpdates: { [weak self] in self?.checkForUpdates(manual: true) },
            installUpdate: { [weak self] in self?.installUpdate() },
            installCommandLineTool: { [weak self] in self?.installCommandLineTool() }
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
        guard alert.runModal() == .alertFirstButtonReturn else {
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
        guard picker.runModal() == .OK else {
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
        model.settingsMessage = nil
        if model.cli == nil {
            model.cli = JitCLI.status()
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
            model.settingsMessage = nil
        } catch {
            model.settingsMessage = "Launch at login: \(error.localizedDescription)"
        }
    }

    /// One `jit service …` invocation, off the main thread: both restart
    /// the service, and consent-off waits on the CLI's own Touch ID prompt.
    /// The stream ends with the restart and reconnects on its own.
    private func applyService(_ arguments: [String]) {
        guard !model.settingsBusy else {
            return
        }
        model.settingsBusy = true
        model.settingsMessage = nil
        Task.detached {
            let result = JitCLI.apply(arguments)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.settingsBusy = false
                switch result {
                case let .success(line): model.settingsMessage = line
                case let .failure(JitCLI.CLIError.failed(line)): model.settingsMessage = line
                case .failure: model.settingsMessage = "jit is not installed where the app can find it."
                }
                pollStatus()
                runDoctor()
            }
        }
    }
}
