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
    /// as a reference; shown only when the `op` CLI is installed.
    @Published var linkOnePassword = true
    @Published var onePasswordInstalled = false
    @Published var showsCommands = false
    /// Whether this Mac had no vault when the window opened.
    @Published var createsVault = false

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
    var done: () -> Void = {}
}
