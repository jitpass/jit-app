// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The setup window (docs/design/onboarding.md): scan, then Protect, as a
/// checklist of the same jit commands the CLI's own first run chains.
extension StatusItemController {
    static let onboardingShownKey = "onboardingShown"

    var onboardingActions: OnboardingActions {
        OnboardingActions(
            quickScan: { [weak self] in self?.onboardingScan(.quick) },
            fullScan: { [weak self] in self?.onboardingFullScan() },
            chooseFolder: { [weak self] in self?.onboardingChooseFolder() },
            openFullDiskAccess: { FullDiskAccess.openSettings() },
            cancelScan: { [weak self] in self?.onboardingCancelScan() },
            back: { [weak self] in self?.onboardingBack() },
            protect: { [weak self] in self?.onboardingProtect() },
            retry: { [weak self] in self?.onboardingRunTasks() },
            notNow: { [weak self] in self?.onboardingWindow.close() },
            openScanReport: { [weak self] in
                self?.onboardingWindow.close()
                self?.openScan()
            },
            done: { [weak self] in self?.onboardingFinish() }
        )
    }

    /// Opens by itself once, on the first launch that finds no vault: an
    /// accessory app otherwise shows a new user nothing but a small ring.
    /// After that, setup is reached from the panel and never reopens itself.
    func openOnboardingOnFirstLaunch() {
        guard model.needsSetup, !UserDefaults.standard.bool(forKey: Self.onboardingShownKey) else {
            return
        }
        UserDefaults.standard.set(true, forKey: Self.onboardingShownKey)
        openOnboarding()
    }

    func openOnboarding() {
        panel.dismiss()
        if !onboardingWindow.isVisible, !onboarding.protecting {
            onboarding.step = .welcome
            onboarding.report = nil
            onboarding.scanError = nil
            onboarding.tasks = []
        }
        onboarding.onePasswordInstalled = JitCLI.onePasswordCLIInstalled
        onboardingWindow.present()
    }

    // MARK: - Scan

    /// Full Scan with the grant starts at once. Without it the screen
    /// explains the switch and a one-second poll starts the scan the
    /// moment macOS reports it, so coming back needs no click.
    private func onboardingFullScan() {
        if FullDiskAccess.granted() {
            onboardingScan(.full)
            return
        }
        onboarding.step = .fullDiskAccess
        onboardingAccessPoll?.invalidate()
        onboardingAccessPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onboardingAccessTick() }
        }
    }

    private func onboardingAccessTick() {
        guard onboarding.step == .fullDiskAccess else {
            onboardingAccessPoll?.invalidate()
            return
        }
        if FullDiskAccess.granted() {
            onboardingScan(.full)
        }
    }

    private func onboardingChooseFolder() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.prompt = "Scan"
        picker.message = "Choose a folder to scan for plaintext secrets."
        guard picker.runModal() == .OK, let url = picker.url else {
            return
        }
        onboardingScan(.folder(url.path))
    }

    private func onboardingScan(_ depth: ScanDepth, then: (@MainActor () -> Void)? = nil) {
        onboardingAccessPoll?.invalidate()
        onboarding.depth = depth
        onboarding.scanLines = 0
        onboarding.scanError = nil
        if then == nil {
            onboarding.step = .scanning
        }
        let run = JitCLI.ScanRun()
        onboardingScanRun = run
        let path: String? = if case let .folder(folder) = depth {
            folder
        } else {
            nil
        }
        let excludes = model.scanExcludes + (depth == .quick ? QuickScan.excludes(home: NSHomeDirectory()) : [])
        Task.detached {
            let result = Result {
                try JitCLI.scan(path: path, excludes: excludes, run: run) { lines in
                    Task { @MainActor [weak self] in self?.onboarding.scanLines = lines }
                }
            }
            await MainActor.run { [weak self] in
                guard let self, !run.cancelled else {
                    return
                }
                onboardingScanned(result, depth: depth)
                then?()
            }
        }
    }

    private func onboardingScanned(_ result: Result<ScanReport, Error>, depth: ScanDepth) {
        switch result {
        case let .success(report):
            onboarding.report = report
            if depth == .full {
                model.macScan = report
                model.macScanAt = Date()
                model.scanStale = false
            }
        case let .failure(error):
            onboarding.report = nil
            onboarding.scanError = Self.describeTools(error)
        }
        guard onboarding.step == .scanning else {
            return
        }
        JitCLI.forgetStatus()
        model.cli = JitCLI.status()
        onboarding.createsVault = model.setup == .needsSetup
        onboarding.tasks = OnboardingPlan.tasks(
            plan: onboarding.report?.protectPlan ?? ProtectPlan(),
            createsVault: onboarding.createsVault
        )
        onboarding.step = .results
    }

    private func onboardingCancelScan() {
        onboardingScanRun?.cancel()
        onboarding.step = .welcome
    }

    private func onboardingBack() {
        onboarding.scanError = nil
        onboarding.step = .welcome
    }

    // MARK: - Protect

    /// The button is the consent: it named the count, and the screen named
    /// the files. The vault state is read again first, because secrets on
    /// disk with no key must go to a recovery file, not a new key.
    private func onboardingProtect() {
        guard vaultAllowsProtect() else {
            return
        }
        onboarding.createsVault = model.setup == .needsSetup
        onboarding.tasks = OnboardingPlan.tasks(
            plan: onboarding.report?.protectPlan ?? ProtectPlan(),
            createsVault: onboarding.createsVault,
            linkOnePassword: onboarding.linkOnePassword
        )
        onboarding.step = .protecting
        onboardingRunTasks()
    }

    /// Runs the first task that is not done, then the next. Each command is
    /// idempotent, so "Try Again" is this same walk from the row that failed.
    func onboardingRunTasks() {
        guard !onboarding.protecting,
              let index = onboarding.tasks.firstIndex(where: { $0.state != .done })
        else {
            return
        }
        onboarding.tasks[index].state = .running
        guard let command = onboarding.tasks[index].command else {
            onboardingScan(onboarding.depth) { [weak self] in
                self?.onboardingProtected(rescanIndex: index)
            }
            return
        }
        Task.detached {
            let result = JitCLI.execute(command)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                switch result {
                case .success:
                    onboarding.tasks[index].state = .done
                    onboardingRunTasks()
                case let .failure(error):
                    onboarding.tasks[index].state = .failed(Self.describeTools(error))
                }
            }
        }
    }

    private func onboardingProtected(rescanIndex index: Int) {
        if let error = onboarding.scanError {
            onboarding.tasks[index].state = .failed(error)
            return
        }
        onboarding.tasks[index].state = .done
        JitCLI.forgetStatus()
        model.cli = JitCLI.status()
        model.scanStale = true
        reloadTools()
        render()
        onboarding.step = .done
    }

    /// After setup: the full panel, shown once so the user sees where
    /// JitPass lives.
    private func onboardingFinish() {
        onboardingWindow.close()
        resync()
        if let button = item.button, !panel.isVisible {
            panel.toggle(under: button)
        }
    }

    func reopened() {
        if model.needsSetup || onboardingWindow.isVisible {
            openOnboarding()
        } else if let button = item.button, !panel.isVisible {
            resync()
            panel.toggle(under: button)
        }
    }

    /// Fixed size, no resize or minimise: one frame, as the mockups draw it.
    func makeOnboardingWindow() -> ReportWindow {
        let size = NSSize(width: OnboardingView.size.width, height: OnboardingView.size.height)
        let window = ReportWindow(
            title: "JitPass Setup",
            content: OnboardingView(model: onboarding, actions: onboardingActions),
            size: size,
            minSize: size
        )
        window.styleMask.remove([.resizable, .miniaturizable])
        window.mayClose = { [weak self] in self?.onboarding.protecting != true }
        return window
    }

    /// A new user is asked one thing at a time: setup owns the first
    /// launch, and the PATH offer waits for one that has a vault.
    func offerCommandLineToolAfterLaunch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard self?.model.needsSetup == false else {
                return
            }
            self?.offerCommandLineToolOnce()
        }
    }
}
