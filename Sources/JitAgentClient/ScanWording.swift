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
    /// A deep scan, always by hand: it reads the vault (ScanMode).
    case deep
    /// The rescan a Protect triggers while a deep report is on screen: the
    /// same depth, so the copies the deep scan found do not vanish from the
    /// window because a Redact ran. Only with the vault open (`afterProtect`).
    case deepAfterProtect

    /// The first words of the Findings header's second line.
    public var label: String {
        switch self {
        case .scheduled: "Scheduled scan"
        case .byHand: "Scanned by hand"
        // The banner above already says a Protect ran.
        case .afterProtect: "Rescanned"
        case .setup: "Scanned during setup"
        case .deep: "Deep scan, by hand"
        case .deepAfterProtect: "Deep rescan"
        }
    }

    /// The run read the vault, so its report holds the vault copies.
    public var isDeep: Bool {
        self == .deep || self == .deepAfterProtect
    }

    /// A Protect's own rescan: the banner it follows stays up.
    public var isAfterProtect: Bool {
        self == .afterProtect || self == .deepAfterProtect
    }

    /// A deep rescan reads the vault first; the session has to outlast that.
    public static let deepRescanMargin: TimeInterval = 30

    /// The kind a Protect's rescan runs as, given the report it replaces.
    ///
    /// A deep report keeps its depth while the vault is open (`unlockedFor`
    /// is the session's remaining time, nil when locked), so every vault
    /// copy is looked for again. Locked, the rescan is regular — a deep
    /// run would need Touch ID, and a prompt with no click behind it is
    /// what the app must never raise — and the deep scan's vault copies
    /// are carried onto its report instead (ScanReport.carryingVaultCopies),
    /// so the window never reads as if the Protect had removed them: 78
    /// findings became 25 after a Redact of 2, when the rescan simply had
    /// not searched for the 53.
    public static func afterProtect(replacing previous: ScanRunKind?, unlockedFor: TimeInterval?) -> ScanRunKind {
        guard previous?.isDeep == true, let unlockedFor, unlockedFor > deepRescanMargin else {
            return .afterProtect
        }
        return .deepAfterProtect
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
    /// A deep scan's finds: how many findings are copies of vaulted secrets.
    public var vaultCopies = 0
    /// When those copies were found, for a regular run that carries them
    /// from an earlier deep scan; nil when this run found them itself.
    public var vaultCopiesFrom: Date?

    public init(
        kind: ScanRunKind, at: Date, schedule: ScanSchedule, newCount: Int?, previousAt: Date?,
        excludes: Int, fullDiskAccess: Bool, vaultCopies: Int = 0, vaultCopiesFrom: Date? = nil
    ) {
        self.kind = kind
        self.at = at
        self.schedule = schedule
        self.newCount = newCount
        self.previousAt = previousAt
        self.excludes = excludes
        self.fullDiskAccess = fullDiskAccess
        self.vaultCopies = vaultCopies
        self.vaultCopiesFrom = vaultCopiesFrom
    }
}

/// The sentences the Findings window says about a run: when it happened,
/// when the next is due, what is new. Pure, so a test can hold them; the
/// clock, calendar and locale are parameters for the same reason.
public enum ScanWording {
    /// The Findings header's second line for a whole-Mac report, each fact
    /// said once: "Scheduled scan · ran Sunday 03:00 · next Sunday 03:00 ·
    /// 2 new since Saturday 03:00 · excluding 1 folder". Nothing new is
    /// silence, the fixtures have their own tab, and what jit reads is
    /// Settings › Scan's; only a missing Full Disk Access, which changes
    /// what the list can hold, is added.
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
        if let newCount = run.newCount, newCount > 0 {
            var fact = "\(newCount) new"
            if let previousAt = run.previousAt {
                fact += " since " + when(previousAt, now: now, calendar: calendar, locale: locale)
            }
            facts.append(fact)
        }
        // The copies themselves are the header's to-do line (ScanTodo); the
        // sentence keeps only where a regular run got them from.
        if run.vaultCopies > 0, let from = run.vaultCopiesFrom {
            facts.append("vault copies from the deep scan " + when(from, now: now, calendar: calendar, locale: locale))
        }
        if run.excludes > 0 {
            facts.append("excluding \(run.excludes) folder" + (run.excludes == 1 ? "" : "s"))
        }
        return facts.joined(separator: " · ") + limit(fullDiskAccess: run.fullDiskAccess)
    }

    /// The same line for a folder scan, which has no schedule and no
    /// previous run: "~/proj · 3 minutes ago. jit reads …".
    public static func folderSubline(
        folder: String,
        at: Date?,
        excludes: Int,
        fullDiskAccess: Bool,
        deep: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var facts = [deep ? "Deep scan of " + folder : folder]
        if let at {
            facts.append(when(at, now: now, calendar: calendar, locale: locale))
        }
        if excludes > 0 {
            facts.append("excluding \(excludes) folder" + (excludes == 1 ? "" : "s"))
        }
        return facts.joined(separator: " · ") + limit(fullDiskAccess: fullDiskAccess)
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
    /// The chooser over an existing report (New Scan…): the report is
    /// not gone, and the sentence says so before it says what a scan reads.
    public static func newScanMessage() -> String {
        "Your last findings stay until this scan replaces them. Choose a folder, or the whole Mac: "
            + "it covers your home folder, shell configs, credential files and agent caches. It only reads, and nothing leaves this Mac."
    }

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

    /// A vault copy's second line: "Line 7 · notion/NOTION_TOKEN". The
    /// secret by its vault name, the scanner's sentence only when jit gave
    /// no name.
    public static func vaultCopyFact(line: Int?, secret: String?, evidence: String?) -> String {
        let what = secret ?? evidence ?? ""
        guard let line else {
            return what
        }
        return what.isEmpty ? "Line \(line)" : "Line \(line) · " + what
    }

    /// Said only when it changes what the list can hold.
    static func limit(fullDiskAccess: Bool) -> String {
        fullDiskAccess ? "" : ". Without Full Disk Access, macOS asks once per protected folder."
    }
}

public extension ScanReport {
    /// The cached copies whose origin is one of these files: what a Protect
    /// of those files will also remove, and so what its dialog must say.
    func copies(from origins: [String]) -> [ScanFinding] {
        let set = Set(origins)
        return agentCopies.filter { $0.originPath.map(set.contains) ?? false }
    }
}

public extension ScanWording {
    /// The Protect dialog's paragraph about the sweep, or nil when the scan
    /// found no copies of these files' secrets. Promises the sweep, not
    /// its outcome: before Touch ID jit knows what it found, not what it
    /// will manage to rewrite.
    ///
    /// "Also removes the 9 copies the scan found in Claude Code's
    /// transcripts and edit history, and in Cursor's chat database." One
    /// sentence: what it could not remove, the banner names afterwards.
    static func sweepSentence(copies: [ScanFinding]) -> String? {
        guard !copies.isEmpty else {
            return nil
        }
        let places = agentPlaces(copies.map { (agent: $0.agent ?? "an AI agent", area: $0.cacheArea) })
        let what = copies.count == 1 ? "the copy" : "the \(copies.count) copies"
        return "Also removes \(what) the scan found in " + places.joined(separator: ", and in ") + "."
    }

    /// Each agent named once, its areas after it, in the order met:
    /// "Claude Code's prompt history and transcripts", "Cursor's cache".
    static func agentPlaces(_ pairs: [(agent: String, area: String?)]) -> [String] {
        var order: [String] = []
        var areas: [String: [String]] = [:]
        for pair in pairs {
            if areas[pair.agent] == nil {
                order.append(pair.agent)
                areas[pair.agent] = []
            }
            if let area = pair.area, areas[pair.agent]?.contains(area) == false {
                areas[pair.agent]?.append(area)
            }
        }
        return order.map { agent in
            let list = areas[agent] ?? []
            return list.isEmpty ? "\(agent)'s cache" : "\(agent)'s " + list.joined(separator: " and ")
        }
    }
}
