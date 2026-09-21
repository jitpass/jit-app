// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Who started a whole-Mac scan. The Findings window owns the schedule,
/// so its header has to say whether the report on screen came from the
/// schedule, a click, a Protect, or setup.
public enum ScanRunKind: String, Sendable {
    case scheduled
    case byHand
    case afterProtect
    case setup

    /// The first words of the Findings header's second line.
    public var label: String {
        switch self {
        case .scheduled: "Scheduled scan"
        case .byHand: "Scanned by hand"
        case .afterProtect: "Scanned after Protect"
        case .setup: "Scanned during setup"
        }
    }
}

public extension ScanSchedule {
    /// When the next scheduled run is due, given the last one. nil when
    /// the schedule never runs on a clock (off, or only at launch).
    func nextRun(after last: Date) -> Date? {
        interval.map { last.addingTimeInterval($0) }
    }
}

/// One whole-Mac run, as the Findings header describes it.
public struct ScanRun: Sendable {
    public var kind: ScanRunKind
    public var at: Date
    public var schedule: ScanSchedule
    /// How many findings the previous run lacked; nil when there was no
    /// previous run to compare with, so nothing is said about what is new.
    public var newCount: Int?
    public var previousAt: Date?
    public var excludes: Int
    public var fullDiskAccess: Bool

    public init(
        kind: ScanRunKind, at: Date, schedule: ScanSchedule, newCount: Int?, previousAt: Date?,
        excludes: Int, fullDiskAccess: Bool
    ) {
        self.kind = kind
        self.at = at
        self.schedule = schedule
        self.newCount = newCount
        self.previousAt = previousAt
        self.excludes = excludes
        self.fullDiskAccess = fullDiskAccess
    }
}

/// The sentences the Findings window says about a run: when it happened,
/// when the next is due, what is new. Pure, so a test can hold them; the
/// clock, calendar and locale are parameters for the same reason.
public enum ScanWording {
    /// The Findings header's second line for a whole-Mac report:
    /// "Scheduled scan · ran Sunday 03:00 · next Sunday 03:00 · 2 new since
    /// Saturday 03:00 · excluding 1 folder. jit reads your home folder, …"
    public static func wholeMacSubline(
        _ run: ScanRun,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var facts: [String] = [run.kind.label]
        let ran = when(run.at, now: now, calendar: calendar, locale: locale)
        facts.append(run.kind == .scheduled ? "ran " + ran : ran)
        facts.append(nextRunFact(schedule: run.schedule, last: run.at, now: now, calendar: calendar, locale: locale))
        if let newCount = run.newCount {
            var fact = newCount == 0 ? "nothing new" : "\(newCount) new"
            if let previousAt = run.previousAt {
                fact += " since " + when(previousAt, now: now, calendar: calendar, locale: locale)
            }
            facts.append(fact)
        }
        if run.excludes > 0 {
            facts.append("excluding \(run.excludes) folder" + (run.excludes == 1 ? "" : "s"))
        }
        return facts.joined(separator: " · ") + ". " + limit(fullDiskAccess: run.fullDiskAccess)
    }

    /// The same line for a folder scan, which has no schedule and no
    /// previous run: "~/proj · 3 minutes ago. jit reads …".
    public static func folderSubline(
        folder: String,
        at: Date?,
        excludes: Int,
        fullDiskAccess: Bool,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var facts = [folder]
        if let at {
            facts.append(when(at, now: now, calendar: calendar, locale: locale))
        }
        if excludes > 0 {
            facts.append("excluding \(excludes) folder" + (excludes == 1 ? "" : "s"))
        }
        return facts.joined(separator: " · ") + ". " + limit(fullDiskAccess: fullDiskAccess)
    }

    /// "next Sunday 03:00", "next at the first chance" when the app slept
    /// through it, "next when JitPass starts", or "no schedule".
    public static func nextRunFact(
        schedule: ScanSchedule,
        last: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        switch schedule {
        case .off:
            return "no schedule"
        case .launch:
            return "next when JitPass starts"
        default:
            guard let next = schedule.nextRun(after: last) else {
                return "no schedule"
            }
            if next <= now {
                return "next at the first chance"
            }
            return "next " + when(next, now: now, calendar: calendar, locale: locale)
        }
    }

    /// What the empty Findings window says before the first scan: that the
    /// schedule will report here on its own, and what a scan now covers.
    public static func emptyMessage(schedule: ScanSchedule) -> String {
        let covers = "the whole Mac covers your home folder, shell configs, credential files and agent caches. "
            + "It only reads, and nothing leaves this Mac."
        switch schedule {
        case .off:
            return "Nothing runs on its own. Scan to see where you stand: " + covers
        case .launch:
            return "A scan runs each time JitPass starts and reports here. Run one now to see where you stand: " + covers
        default:
            return "A scan runs on its own \(schedule.label.lowercased()) and reports here. "
                + "Run one now to see where you stand: " + covers
        }
    }

    /// A moment, in the words a person uses for it: "just now", "in 3
    /// hours", "Sunday 03:00" inside a week, "12 Sep" beyond it. Both
    /// directions, since the next run is in the future.
    public static func when(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let delta = now.timeIntervalSince(date)
        let past = delta >= 0
        let seconds = abs(delta)
        if seconds < 90 {
            return past ? "just now" : "in a moment"
        }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return past ? "\(minutes) min ago" : "in \(minutes) min"
        }
        let hours = Int((seconds / 3600).rounded())
        if hours < 24 {
            let unit = hours == 1 ? "hour" : "hours"
            return past ? "\(hours) \(unit) ago" : "in \(hours) \(unit)"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        if seconds < 7 * 86400 {
            formatter.setLocalizedDateFormatFromTemplate("EEEE HH:mm")
            return formatter.string(from: date)
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "d MMM" : "d MMM yyyy")
        return formatter.string(from: date)
    }

    static func limit(fullDiskAccess: Bool) -> String {
        fullDiskAccess
            ? "jit reads your home folder, shell configs, credential files and agent caches."
            : "Without Full Disk Access, macOS asks once per protected folder."
    }
}
