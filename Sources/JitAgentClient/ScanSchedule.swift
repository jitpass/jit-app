// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// How often the app scans the whole Mac on its own, so the Findings row
/// is a standing state rather than the result of whichever scan was last
/// clicked. The user picks it in Settings; `off` means every scan is a
/// click. Kept as plain Foundation so the due rule is unit-tested.
public enum ScanSchedule: String, CaseIterable, Sendable {
    case off
    case launch
    case hourly
    case daily
    case weekly
    case monthly

    public static let `default` = ScanSchedule.daily
    public static let preferenceKey = "BackgroundScan"

    public var label: String {
        switch self {
        case .off: "Never"
        case .launch: "When JitPass starts"
        case .hourly: "Every hour"
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }

    /// The gap after which a scan is due again; nil when only a launch
    /// (or a change jit made) triggers one.
    public var interval: TimeInterval? {
        switch self {
        case .off, .launch: nil
        case .hourly: 3600
        case .daily: 86400
        case .weekly: 7 * 86400
        case .monthly: 30 * 86400
        }
    }

    /// Whether a background scan should run now. `last` is the previous
    /// whole-Mac scan this process ran; nil means none yet, which is due
    /// for every schedule but `off`.
    public func isDue(last: Date?, now: Date = Date()) -> Bool {
        guard self != .off else {
            return false
        }
        guard let last else {
            return true
        }
        guard let interval else {
            return false
        }
        return now.timeIntervalSince(last) >= interval
    }
}
