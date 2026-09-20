// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The Settings window's three segments. Seven cards are two and a half
/// screens at 520 wide, so the toolbar splits them where the question
/// changes: what jit hands out, what reads your disk, how the app behaves
/// on this Mac (docs/design: windows.md, "Segmented filter").
public enum SettingsSegment: String, CaseIterable, Identifiable, Sendable {
    case protection
    case scan
    case app

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .protection: "Protection"
        case .scan: "Scan"
        case .app: "App"
        }
    }

    public var groups: [SettingsGroup] {
        SettingsGroup.allCases.filter { $0.segment == self }
    }
}

/// One card. The eyebrow carries the group's name and its state, in
/// reading order within each segment.
public enum SettingsGroup: String, CaseIterable, Identifiable, Sendable {
    case protection
    case notifications
    case vault
    case scan
    case thisMac
    case updates
    case remove

    public var id: String {
        rawValue
    }

    public var segment: SettingsSegment {
        switch self {
        case .protection, .notifications, .vault: .protection
        case .scan: .scan
        case .thisMac, .updates, .remove: .app
        }
    }

    public var title: String {
        switch self {
        case .protection: "Protection"
        case .notifications: "Notifications"
        case .vault: "Vault"
        case .scan: "Scan"
        case .thisMac: "This Mac"
        case .updates: "Updates"
        case .remove: "Remove"
        }
    }
}

/// What a card's dot says. `none` is a card with nothing to be healthy
/// about — emptying the vault and removing the app are things you do, not
/// states you are in — and it draws the plain dot, never green.
public enum SettingsState: Sendable, Equatable {
    case none
    case healthy
    case needsYou
}

/// Everything the window's dots depend on, in one value a test can build.
/// Each field is a fact the app already has; none of them is a guess.
public struct SettingsFacts: Equatable, Sendable {
    /// Whether jit answered at all. Both settings jit owns are unusable
    /// without it, so its card is the one that says so.
    public var serviceRunning: Bool
    /// Either notification switch is on.
    public var notificationsWanted: Bool
    /// macOS will not deliver: denied, or never asked.
    public var notificationsBlocked: Bool
    /// The schedule is anything but off.
    public var scanScheduled: Bool
    public var fullDiskAccess: Bool
    public var updateAvailable: Bool
    public var jitOnPath: Bool

    public init(
        serviceRunning: Bool = true,
        notificationsWanted: Bool = false,
        notificationsBlocked: Bool = false,
        scanScheduled: Bool = false,
        fullDiskAccess: Bool = true,
        updateAvailable: Bool = false,
        jitOnPath: Bool = true
    ) {
        self.serviceRunning = serviceRunning
        self.notificationsWanted = notificationsWanted
        self.notificationsBlocked = notificationsBlocked
        self.scanScheduled = scanScheduled
        self.fullDiskAccess = fullDiskAccess
        self.updateAvailable = updateAvailable
        self.jitOnPath = jitOnPath
    }
}

public extension SettingsFacts {
    /// A card is amber only for something the reader can act on here.
    /// Notifications are blocked only where they were asked for; the scan
    /// waits on Full Disk Access only where a scan is scheduled to run
    /// without anyone present.
    func state(of group: SettingsGroup) -> SettingsState {
        switch group {
        case .protection: serviceRunning ? .healthy : .needsYou
        case .notifications: notificationsWanted && notificationsBlocked ? .needsYou : .healthy
        case .scan: scanScheduled && !fullDiskAccess ? .needsYou : .healthy
        case .thisMac: .healthy
        case .updates: updateAvailable || !jitOnPath ? .needsYou : .healthy
        case .vault, .remove: .none
        }
    }

    /// The dot a segment's pill carries: amber when a card behind it needs
    /// the reader, nothing when they are all well. A row of green dots on
    /// a filter says nothing and costs the eye the same.
    func needsYou(in segment: SettingsSegment) -> Bool {
        segment.groups.contains { state(of: $0) == .needsYou }
    }

    /// Every segment, in order. All three always show: unlike a scan's
    /// tiers, a settings group cannot be empty.
    var segments: [SettingsSegment] {
        SettingsSegment.allCases
    }
}
