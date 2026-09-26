// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The Settings window's five segments, each one card or two, so every
/// tab opens without a scroll (docs/design/mockups/Settings-v2.html). What
/// deletes or removes has its own segment, so nothing red sits beside a
/// switch someone flips every week.
public enum SettingsSegment: String, CaseIterable, Identifiable, Sendable {
    case general
    case protection
    case notifications
    case scan
    case reset

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .general: "General"
        case .protection: "Protection"
        case .notifications: "Notifications"
        case .scan: "Scan"
        case .reset: "Reset"
        }
    }

    public var groups: [SettingsGroup] {
        SettingsGroup.allCases.filter { $0.segment == self }
    }
}

/// One card, in reading order within each segment. A segment's lone card
/// carries no eyebrow: the pill above it already says what it is.
public enum SettingsGroup: String, CaseIterable, Identifiable, Sendable {
    case general
    case protection
    case notifications
    case scan
    case excludes
    case reset

    public var id: String {
        rawValue
    }

    public var segment: SettingsSegment {
        switch self {
        case .general: .general
        case .protection: .protection
        case .notifications: .notifications
        case .scan, .excludes: .scan
        case .reset: .reset
        }
    }

    public var title: String {
        switch self {
        case .general: "General"
        case .protection: "Protection"
        case .notifications: "Notifications"
        case .scan: "Scan"
        case .excludes: "Folders every scan skips"
        case .reset: "Reset"
        }
    }
}

/// What a card's state is, for the dot on its segment's pill. `none` is a
/// card with nothing to be healthy about: emptying the vault, removing the
/// app and a list of skipped folders are things you do, not states you
/// are in.
public enum SettingsState: Sendable, Equatable {
    case none
    case healthy
    case needsYou
    /// Something only you can fix: jit is not running. Red, as the
    /// panel's Service row is.
    case broken
}

/// Everything the window's dots depend on, in one value a test can build.
/// Each field is a fact the app already has; none of them is a guess.
public struct SettingsFacts: Equatable, Sendable {
    /// Whether jit answered at all. Both settings jit owns are unusable
    /// without it, so its card is the one that says so.
    public var serviceRunning: Bool
    /// Any notification switch is on.
    public var notificationsWanted: Bool
    /// macOS will not deliver: denied, or never asked.
    public var notificationsBlocked: Bool
    /// The schedule is anything but off.
    public var scanScheduled: Bool
    public var fullDiskAccess: Bool
    public var updateAvailable: Bool
    public var jitOnPath: Bool
    /// The vault key row's state, nil where the row is not drawn.
    public var vaultKey: VaultKeyRow?

    public init(
        serviceRunning: Bool = true,
        notificationsWanted: Bool = false,
        notificationsBlocked: Bool = false,
        scanScheduled: Bool = false,
        fullDiskAccess: Bool = true,
        updateAvailable: Bool = false,
        jitOnPath: Bool = true,
        vaultKey: VaultKeyRow? = nil
    ) {
        self.serviceRunning = serviceRunning
        self.notificationsWanted = notificationsWanted
        self.notificationsBlocked = notificationsBlocked
        self.scanScheduled = scanScheduled
        self.fullDiskAccess = fullDiskAccess
        self.updateAvailable = updateAvailable
        self.jitOnPath = jitOnPath
        self.vaultKey = vaultKey
    }
}

public extension SettingsFacts {
    /// A card is amber only for something the reader can act on here, and
    /// red only when jit itself is down.
    /// Notifications are blocked only where they were asked for; the scan
    /// waits on Full Disk Access only where a scan is scheduled to run
    /// without anyone present.
    func state(of group: SettingsGroup) -> SettingsState {
        switch group {
        case .protection: serviceRunning ? vaultKey?.settingsState ?? .healthy : .broken
        case .notifications: notificationsWanted && notificationsBlocked ? .needsYou : .healthy
        case .scan: scanScheduled && !fullDiskAccess ? .needsYou : .healthy
        case .general: updateAvailable || !jitOnPath ? .needsYou : .healthy
        case .excludes, .reset: .none
        }
    }

    /// Whether a segment's pill carries a dot: a card behind it needs the
    /// reader. Nothing when they are all well: a row of green dots on a
    /// filter says nothing and costs the eye the same.
    func needsYou(in segment: SettingsSegment) -> Bool {
        worst(in: segment) != nil
    }

    /// The state the pill's dot shows: red before amber.
    func worst(in segment: SettingsSegment) -> SettingsState? {
        let states = segment.groups.map { state(of: $0) }
        if states.contains(.broken) {
            return .broken
        }
        return states.contains(.needsYou) ? .needsYou : nil
    }

    /// Every segment, in order. All five always show: unlike a scan's
    /// tiers, a settings group cannot be empty.
    var segments: [SettingsSegment] {
        SettingsSegment.allCases
    }
}

public extension VaultKeyRow {
    /// What the row's dot says, for the Protection pill: red where nothing
    /// opens or nothing may change until you act, amber for a question or
    /// a move to finish, and healthy otherwise. The same colours the row
    /// draws.
    var settingsState: SettingsState {
        switch self {
        case .lost, .restorePending, .changeUnknown, .copyInKeychain: .broken
        case .unfinished, .restoreUnchecked: .needsYou
        case .keychain, .secureEnclave, .checking, .unchecked: .healthy
        }
    }
}
