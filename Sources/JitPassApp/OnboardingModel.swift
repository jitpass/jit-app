// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// What the setup window shows, as plain values the controller writes and
/// the view reads, the same split as `MenuModel`.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    /// The depth the user chose; kept so "Try Again" and the closing
    /// rescan look in the same places the first scan did.
    @Published var depth: ScanDepth = .quick
    @Published var report: ScanReport?
    /// Records `jit scan` has emitted so far, while it runs.
    @Published var scanLines = 0
    @Published var scanError: String?
    @Published var tasks: [OnboardingTask] = []
    /// Whether migrate may store a value that already lives in 1Password
    /// as a reference; shown only when the `op` CLI is installed. Off
    /// until asked for: the check reads every item in the account, which
    /// put minutes of bare spinner into a first run.
    @Published var linkOnePassword = false
    @Published var onePasswordInstalled = false
    @Published var showsCommands = false
    /// Whether this Mac had no vault when the window opened.
    @Published var createsVault = false

    // The finish screen's switches. They are choices, applied together by
    // Done, so macOS asks about notifications at a moment the user expects.
    @Published var launchAtLogin = true
    @Published var notify = true
    /// Off by default: it adds a line to the user's ~/.zshrc.
    @Published var historyGuard = false
    @Published var installCLI = false
    /// The guard is a zsh hook; the row is hidden for any other login shell.
    @Published var offersGuard = false
    /// Only when a terminal would not find `jit` and Homebrew is not the one to fix it.
    @Published var offersCLI = false
    /// Where the recovery file went, once it has.
    @Published var recoverySaved: String?
    @Published var finishBusy: String?
    /// What did not apply, one line each; Done still closes on the next press.
    @Published var finishProblems: [String] = []
    @Published var finishApplied = false
    /// The files this setup rewrote: what Undo restores.
    @Published var migratedFiles: [String] = []

    @Published var restoreFile: String?
    @Published var restorePassphrase = ""
    @Published var restoreBusy = false
    @Published var restoreError: String?
    /// Secrets stored here that no key opens, when that is why Restore is
    /// on screen; 0 for someone arriving from another Mac.
    @Published var strandedSecrets = 0

    var protecting: Bool {
        tasks.contains { $0.state == .running }
    }

    var failedTask: OnboardingTask? {
        tasks.first {
            if case .failed = $0.state {
                return true
            }
            return false
        }
    }

    /// Secrets still sitting in plain text.
    var exposed: Int {
        guard let s = report?.summary else {
            return 0
        }
        return max(0, s.secretsTotal - s.secretsProtected)
    }

    /// What a quick or folder scan did not look at, in words; nil after a full one.
    var notScanned: String? {
        switch depth {
        case .quick: "Desktop, Documents and Downloads were not scanned."
        case let .folder(path): "Only \(Format.home(path)) was scanned."
        case .full: nil
        }
    }
}

/// What the setup window can ask the controller to do.
struct OnboardingActions {
    var quickScan: () -> Void = {}
    var fullScan: () -> Void = {}
    var chooseFolder: () -> Void = {}
    var openFullDiskAccess: () -> Void = {}
    var cancelScan: () -> Void = {}
    var back: () -> Void = {}
    var protect: () -> Void = {}
    var retry: () -> Void = {}
    var notNow: () -> Void = {}
    var openScanReport: () -> Void = {}
    var quit: () -> Void = {}
    var showRestore: () -> Void = {}
    var chooseRestoreFile: () -> Void = {}
    var restore: () -> Void = {}
    var saveRecovery: () -> Void = {}
    var undo: () -> Void = {}
    var done: () -> Void = {}
}
