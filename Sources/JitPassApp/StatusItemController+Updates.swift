// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Updates and the command line tool: what a copy downloaded from the
/// website needs that the cask otherwise does. A Homebrew install keeps
/// both with `brew upgrade`; this only ever sends it there.
extension StatusItemController {
    static let updateCheckInterval: TimeInterval = 6 * 60 * 60
    static let cliOfferKey = "OfferedCommandLineTool"

    func startUpdateChecks() {
        model.checkForUpdates = UpdateCheck.enabled
        model.updateChecked = UpdateCheck.lastCheck
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.checkForUpdatesIfDue()
        }
        updateCheck = Timer.scheduledTimer(withTimeInterval: Self.updateCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdatesIfDue() }
        }
    }

    func checkForUpdatesIfDue() {
        guard UpdateCheck.isDue else {
            return
        }
        checkForUpdates(manual: false)
    }

    /// Manual from Settings says what it found either way; the daily one
    /// only speaks when there is something to install.
    func checkForUpdates(manual: Bool) {
        guard !model.updateChecking else {
            return
        }
        model.updateChecking = true
        if manual {
            model.updateMessage = nil
        }
        Task.detached {
            let outcome = await UpdateCheck.run()
            await MainActor.run { [weak self] in
                self?.finishUpdateCheck(outcome, manual: manual)
            }
        }
    }

    private func finishUpdateCheck(_ outcome: UpdateCheck.Outcome, manual: Bool) {
        model.updateChecking = false
        model.updateChecked = UpdateCheck.lastCheck
        switch outcome {
        case let .available(version):
            model.updateAvailable = "\(version)"
            if manual {
                model.updateMessage = "JitPass \(version) is available."
            }
        case .upToDate:
            model.updateAvailable = nil
            if manual {
                model.updateMessage = "JitPass \(UpdateCheck.current.map { "\($0)" } ?? "") is the latest version."
            }
        case let .failed(reason):
            if manual {
                model.updateMessage = "Could not check: \(reason)"
            }
        }
    }

    func setCheckForUpdates(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: UpdateCheck.preferenceKey)
        model.checkForUpdates = on
        if on {
            checkForUpdatesIfDue()
        }
    }

    /// Homebrew installs update the Homebrew way; a downloaded copy is
    /// replaced by hand, from the same link the website prints.
    func installUpdate() {
        panel.dismiss()
        guard let version = model.updateAvailable else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "JitPass \(version) is available"
        if CommandLineTool.installedByHomebrew() {
            alert.informativeText = "This copy was installed with Homebrew. The update runs in the terminal:\n\n"
                + "brew upgrade jitpass\n\nThe service keeps running and restarts itself onto the new version."
            alert.addButton(withTitle: "Open in Terminal")
            alert.addButton(withTitle: "Later")
            guard alert.runFrontmost() == .alertFirstButtonReturn else {
                return
            }
            runInTerminal("brew update && brew upgrade jitpass")
        } else {
            alert.informativeText = "The download opens in your browser. Quit JitPass, replace it in Applications, and open it again."
                + "\n\nYour vault and settings stay."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            guard alert.runFrontmost() == .alertFirstButtonReturn else {
                return
            }
            NSWorkspace.shared.open(AppUpdate.downloadURL)
        }
    }

    // MARK: - Command line tool

    /// The jit inside this bundle, nil for a dev build run from .build/.
    var bundledJit: String? {
        CommandLineTool.bundledJit(in: Bundle.main.bundleURL)
    }

    func refreshCommandLineTool() {
        guard let bundledJit else {
            model.cliTool = nil
            return
        }
        Task.detached {
            let state = CommandLineTool.state(bundled: bundledJit, path: LoginShell.path)
            await MainActor.run { [weak self] in self?.model.cliTool = state }
        }
    }

    /// Once, on a launch where a terminal would not find jit and Homebrew
    /// is not the one to fix it: the same offer Settings keeps.
    func offerCommandLineToolOnce() {
        guard let bundledJit, !UserDefaults.standard.bool(forKey: Self.cliOfferKey),
              !CommandLineTool.installedByHomebrew()
        else {
            return
        }
        Task.detached {
            let state = CommandLineTool.state(bundled: bundledJit, path: LoginShell.path)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.cliTool = state
                guard state == .missing else {
                    return
                }
                UserDefaults.standard.set(true, forKey: Self.cliOfferKey)
                let alert = NSAlert()
                alert.messageText = "Install the jit command line tool?"
                alert.informativeText = "The app carries the jit CLI. A link in your PATH lets a terminal run it "
                    + "as `jit`. You can do this later from Settings › General."
                alert.addButton(withTitle: "Install")
                alert.addButton(withTitle: "Not Now")
                if alert.runFrontmost() == .alertFirstButtonReturn {
                    installCommandLineTool()
                }
            }
        }
    }

    /// Links `<dir>/jit` at the bundled copy: Homebrew's bin without a
    /// password when it is there and writable, else /usr/local/bin with
    /// the system's own administrator prompt.
    func installCommandLineTool() {
        guard let bundledJit else {
            return
        }
        let target = CommandLineTool.linkTarget(path: LoginShell.path)
        let link = (target.directory as NSString).appendingPathComponent("jit")
        if case let .other(existing)? = model.cliTool, existing != link {
            let alert = NSAlert()
            alert.messageText = "Another jit comes first"
            alert.informativeText = "A terminal runs \(existing) before \(link). Remove or rename that copy, "
                + "or the link this installs is never reached."
            alert.addButton(withTitle: "Install Anyway")
            alert.addButton(withTitle: "Cancel")
            guard alert.runFrontmost() == .alertFirstButtonReturn else {
                return
            }
        }
        let outcome: String? = if target.needsAdmin {
            Self.linkAsAdmin(from: link, to: bundledJit)
        } else {
            Self.link(from: link, to: bundledJit)
        }
        model.settingsOutcome = outcome.map { SettingsOutcome.failed(.commandLineTool, line: $0) }
            ?? .applied(.commandLineTool, value: "jit is on your PATH at \(link). Open a new terminal to use it.")
        refreshCommandLineTool()
    }

    private static func link(from link: String, to target: String) -> String? {
        do {
            if FileManager.default.fileExists(atPath: link) || (try? FileManager.default.destinationOfSymbolicLink(atPath: link)) != nil {
                try FileManager.default.removeItem(atPath: link)
            }
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
            return nil
        } catch {
            return "Could not link \(link): \(error.localizedDescription)"
        }
    }

    /// One `do shell script … with administrator privileges`: macOS shows
    /// its own password dialog naming the app, and the command is fixed
    /// except for the two quoted paths.
    private static func linkAsAdmin(from link: String, to target: String) -> String? {
        let directory = (link as NSString).deletingLastPathComponent
        let shell = "mkdir -p \(Terminal.quoted(directory)) && ln -sfn \(Terminal.quoted(target)) \(Terminal.quoted(link))"
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else {
            return nil
        }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 {
            return "Cancelled."
        }
        return "Could not link \(link): \(error[NSAppleScript.errorMessage] as? String ?? "unknown error")"
    }
}
