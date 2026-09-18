// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The setup window's pure half (docs/design/onboarding.md): which screen,
/// which folders a quick scan leaves alone, and which commands a Protect
/// runs. No AppKit and no process, so all of it is unit-tested.
public enum OnboardingStep: Equatable, Sendable {
    case welcome
    /// Full Scan was chosen and macOS has not granted Full Disk Access.
    case fullDiskAccess
    case scanning
    case results
    case protecting
    case done
    /// A recovery file and its passphrase: a new Mac, or secrets on disk
    /// whose key is gone.
    case restore
    /// macOS is running the app from a temporary path; setup must not start.
    case moveToApplications
}

/// How deep the first look goes. The user chooses; the app does not.
public enum ScanDepth: Equatable, Sendable {
    /// Skips the folders macOS guards, so it can never raise a prompt.
    case quick
    case full
    case folder(String)
}

public enum QuickScan {
    /// The home folders macOS asks about one by one without Full Disk
    /// Access. The scan already stays out of ~/Library and the media
    /// libraries (jit's `noiseDirs`), so these three are the whole list.
    public static let skippedNames = ["Desktop", "Documents", "Downloads"]

    public static func excludes(home: String) -> [String] {
        skippedNames.map { (home as NSString).appendingPathComponent($0) }
    }
}

/// One row of the protecting checklist: a command and how it went.
public struct OnboardingTask: Equatable, Sendable, Identifiable {
    public enum State: Equatable, Sendable {
        case pending
        case running
        case done
        case failed(String)
    }

    public enum Kind: Equatable, Sendable {
        case createVault
        case migrate
        case wrap(String)
        /// A fresh scan, so the closing number is measured, not promised.
        case rescan
    }

    public var kind: Kind
    public var title: String
    public var detail: String
    /// The jit arguments; nil for the rescan, which the app runs itself.
    public var command: [String]?
    public var state: State = .pending

    public var id: String {
        title
    }
}

public enum OnboardingPlan {
    /// The checklist for one Protect, in the order it must run: the vault
    /// before anything that writes to it, one migrate for every file (one
    /// plan, one Touch ID), each tool, then the rescan.
    public static func tasks(plan: ProtectPlan, createsVault: Bool, linkOnePassword: Bool = true) -> [OnboardingTask] {
        var tasks: [OnboardingTask] = []
        if createsVault {
            tasks.append(OnboardingTask(
                kind: .createVault, title: "Create the vault",
                detail: "The key goes in your login keychain, on this Mac only.",
                command: ["vault", "init"]
            ))
        }
        if !plan.migrate.isEmpty {
            let files = plan.migrate.count == 1 ? "1 file" : "\(plan.migrate.count) files"
            tasks.append(OnboardingTask(
                kind: .migrate, title: "Move the secrets, rewrite \(files)",
                detail: linkOnePassword
                    ? "Touch ID follows. Checking 1Password first reads every item there, which can take a few minutes."
                    : "Touch ID follows. Each file is backed up, encrypted, before it is touched.",
                command: ["migrate"] + plan.migrate + ["--yes"] + (linkOnePassword ? [] : ["--no-1password"])
            ))
        }
        for tool in plan.wrap {
            tasks.append(OnboardingTask(
                kind: .wrap(tool), title: "Protect \(tool)",
                detail: "It gets its key from the vault each time it runs.",
                command: ["wrap", tool]
            ))
        }
        guard !tasks.isEmpty else {
            return []
        }
        tasks.append(OnboardingTask(
            kind: .rescan, title: "Check the result",
            detail: "A fresh scan, so the number you see is real."
        ))
        return tasks
    }

    /// The commands as the user would type them, for "What this runs".
    public static func commandLines(_ tasks: [OnboardingTask], home: String) -> [String] {
        tasks.compactMap(\.command).map { arguments in
            "jit " + arguments.map { $0.hasPrefix(home) ? "~" + $0.dropFirst(home.count) : $0 }.joined(separator: " ")
        }
    }
}
