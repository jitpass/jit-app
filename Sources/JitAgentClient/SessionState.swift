// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What the menu bar shows, derived from one `status` round trip. Kept as a
/// plain value so the rendering layer has nothing to compute and the
/// derivation is unit-tested without AppKit.
public enum SessionState: Equatable, Sendable {
    case notRunning
    case locked(reason: String?)
    case unlocked(expiresIn: TimeInterval)

    public init(response: AgentResponse) {
        if response.unlocked == true {
            self = .unlocked(expiresIn: TimeInterval(response.expiresInSeconds ?? 0))
        } else {
            self = .locked(reason: response.lastLock?.cause)
        }
    }

    /// The one-word headline of the dropdown.
    public var headline: String {
        switch self {
        case .notRunning: "Service not running"
        case .locked: "Locked"
        case .unlocked: "Unlocked"
        }
    }

    /// The secondary line under the headline.
    public var detail: String {
        switch self {
        case .notRunning: "run jit unlock to start it"
        case let .locked(reason?): reason
        case .locked: "session ended"
        case let .unlocked(expiresIn): "locks in \(Self.countdown(expiresIn))"
        }
    }

    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
