// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient

/// Everything the Settings window can ask the controller to do. One method
/// per control, so the view holds no policy.
struct SettingsActions {
    var addExclude: () -> Void = {}
    var removeExclude: (String) -> Void = { _ in }
    var setTerminal: (String) -> Void = { _ in }
    var setEditor: (String) -> Void = { _ in }
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var setScanSchedule: (ScanSchedule) -> Void = { _ in }
    var setRedactAfterScan: (Bool) -> Void = { _ in }
    var grantFullDiskAccess: () -> Void = {}
    /// The value jit is given, and the words the banner says it in.
    var setTTL: (String, String) -> Void = { _, _ in }
    var setConsent: (Bool) -> Void = { _ in }
    var setGuard: (Bool) -> Void = { _ in }
    var setNotifyDecoys: (Bool) -> Void = { _ in }
    var setNotifyChanges: (Bool) -> Void = { _ in }
    var setNotifyJobs: (Bool) -> Void = { _ in }
    var allowNotifications: () -> Void = {}
    var openNotificationSettings: () -> Void = {}
    var vaultClean: () -> Void = {}
    var vaultDelete: () -> Void = {}
    var setCheckForUpdates: (Bool) -> Void = { _ in }
    var checkForUpdates: () -> Void = {}
    var installUpdate: () -> Void = {}
    var installCommandLineTool: () -> Void = {}
    var removeJitPass: () -> Void = {}
    /// Offered only where jit's own line says the service being down is
    /// what stopped the change.
    var startService: () -> Void = {}
}
