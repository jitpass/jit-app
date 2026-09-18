// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// What the Remove JitPass window shows, as plain values the controller
/// writes and the view reads, the same split as `OnboardingModel`.
@MainActor
final class OffboardingModel: ObservableObject {
    @Published var step: OffboardingStep = .loading
    @Published var plan = UninstallPlan()
    @Published var tasks: [OnboardingTask] = []
    @Published var failures: [UninstallEvent.Failure] = []
    /// What removal finished without: shown on Done, never hidden.
    @Published var problems: [String] = []
    /// Why a run that was neither of those stopped (a declined Touch ID).
    @Published var stopped: String?
    /// Where the recovery file went, once it has.
    @Published var recoverySaved: String?
    @Published var recoveryBusy = false
    @Published var recoveryError: String?
    @Published var showsCommands = false
    /// Homebrew installed this copy: brew removes the app, not the Trash.
    @Published var homebrew = false
    /// Another `jit` on PATH that is not this app's; left alone, and named.
    @Published var otherJit: String?

    /// True while jit or the app's own step is changing things: the window
    /// and Quit both wait for it.
    var removing: Bool {
        step == .removing && stopped == nil
    }

    /// Whether Remove restores files first. Not when the vault's key is
    /// gone: nothing in it can be read, so there is nothing to put back.
    var restoring: Bool {
        plan.keyPresent
    }

    var command: [String] {
        restoring ? OffboardingPlan.restoreCommand : OffboardingPlan.purgeCommand
    }
}

/// What the Remove JitPass window can ask the controller to do.
struct OffboardingActions {
    var cancel: () -> Void = {}
    var next: () -> Void = {}
    var back: () -> Void = {}
    var saveRecovery: () -> Void = {}
    var remove: () -> Void = {}
    var tryAgain: () -> Void = {}
    var removeAnyway: () -> Void = {}
    var show: (String) -> Void = { _ in }
    var finish: () -> Void = {}
}
