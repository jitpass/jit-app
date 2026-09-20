// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What the menu bar shows, derived from one `status` round trip. Kept as a
/// plain value so the rendering layer has nothing to compute and the
/// derivation is unit-tested without AppKit.
public enum SessionState: Equatable, Sendable {
    case notRunning
    case locked(reason: String?)
    /// `ceilingAt` is the hard session ceiling as a wall-clock time, nil from
    /// an agent that predates the field.
    case unlocked(expiresIn: TimeInterval, ceilingAt: Date?)

    public init(response: AgentResponse, now: Date = Date()) {
        if response.unlocked == true {
            let ceiling = response.ceilingInSeconds.map { now.addingTimeInterval(TimeInterval($0)) }
            self = .unlocked(expiresIn: TimeInterval(response.expiresInSeconds ?? 0), ceilingAt: ceiling)
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
        case .notRunning:
            return "run jit unlock to start it"
        case let .locked(reason?):
            return reason
        case .locked:
            return "session ended"
        case let .unlocked(expiresIn, ceilingAt):
            let base = "locks in \(Self.countdown(expiresIn))"
            guard let ceilingAt else {
                return base
            }
            return base + " · no later than \(Self.clock(ceilingAt))"
        }
    }

    static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    public static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    /// `M:SS` under an hour, `H:MM:SS` at or above it. The minutes field is
    /// minutes, not "everything that isn't seconds": an 8h TTL rendered the
    /// first way reads "locks in 463:25", which is not a time anyone can read.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
