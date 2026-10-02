// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

public extension ServiceLog {
    /// One day of the log, newest first, as Show Log draws it.
    struct Day: Equatable, Sendable {
        /// "Today", "Yesterday", or the date as jit wrote it.
        public var label: String
        public var entries: [Entry]
    }

    /// The parsed rows grouped by day, newest day and newest row first.
    /// `today` is "YYYY-MM-DD" in the Mac's own calendar. A raw line (one
    /// jit didn't recognise) joins the day of the row before it in the
    /// file, where it was written.
    func days(today: String, yesterday: String) -> [Day] {
        var order: [String] = []
        var byDay: [String: [Entry]] = [:]
        var current = ""
        for entry in entries {
            if let date = entry.date {
                current = date
            }
            if byDay[current] == nil {
                order.append(current)
            }
            byDay[current, default: []].append(entry)
        }
        return order.reversed().map { date in
            let label = date == today ? "Today" : date == yesterday ? "Yesterday" : date.isEmpty ? "Earlier" : date
            return Day(label: label, entries: (byDay[date] ?? []).reversed())
        }
    }

    /// `date` as jit writes a log day: Gregorian `YYYY-MM-DD`, Latin
    /// digits, in the Mac's time zone, whatever its calendar or locale (a
    /// Mac on the Hebrew calendar would otherwise never match "Today").
    static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `days(today:yesterday:)` for `now`, labelled in jit's own calendar.
    func days(now: Date, timeZone: TimeZone = .current) -> [Day] {
        let yesterday = now.addingTimeInterval(-24 * 60 * 60)
        return days(today: Self.day(now, timeZone: timeZone), yesterday: Self.day(yesterday, timeZone: timeZone))
    }

    /// The rows as plain lines, for Copy: a bug report wants the words, not
    /// the layout.
    var plainText: String {
        entries.map { entry in
            if let raw = entry.raw {
                return raw
            }
            let subjects = (entry.subjects ?? []).joined(separator: ", ")
            return [entry.date, entry.time, entry.message, subjects.isEmpty ? nil : "(" + subjects + ")"]
                .compactMap { $0 }.joined(separator: " ")
        }.joined(separator: "\n")
    }
}

/// The rows under a Doctor confirmation (Migrate, Undo Migration), in place
/// of jit's dry-run text: what happens to each variable or file.
public struct PlanRow: Equatable, Sendable {
    public var name: String
    /// The folder, or a setting's value: the grey half of the row's name.
    public var detail: String
    /// Where it goes: "Vault", "Stays as a setting", "Back in plain text".
    public var badge: String
    /// Whether the badge is the vault's (green) or a neutral one.
    public var toVault: Bool

    public init(name: String, detail: String = "", badge: String, toVault: Bool) {
        self.name = name
        self.detail = detail
        self.badge = badge
        self.toVault = toVault
    }

    /// A migrate's rows, from `jit migrate preview`: each .env variable by
    /// where it goes (a setting with its value, a secret never), and each
    /// other file as one row. "check" is a value jit is not sure about; it
    /// goes to the vault unless the user says otherwise, so it reads Vault.
    public static func migrate(_ preview: MigratePreview) -> [PlanRow] {
        preview.files.flatMap { file -> [PlanRow] in
            let name = (file.path as NSString).lastPathComponent
            switch file.kind {
            case "env":
                let vars = file.vars ?? []
                guard !vars.isEmpty else {
                    return [PlanRow(name: name, detail: folder(file.path), badge: "Nothing to move", toVault: false)]
                }
                return vars.map { variable in
                    variable.varClass == "setting"
                        ? PlanRow(name: variable.name, detail: variable.value ?? "", badge: "Stays as a setting", toVault: false)
                        : PlanRow(name: variable.name, badge: variable.inVault ? "Already in the vault" : "Vault", toVault: true)
                }
            default:
                return [PlanRow(name: name, detail: folder(file.path), badge: "Vault", toVault: true)]
            }
        }
    }

    /// A migrate by category (`jit migrate --only aws`): doctor asks it to
    /// refresh the jit path recorded in a credential helper, and names
    /// each file on its finding. No preview exists for a category, so the
    /// rows are those files.
    public static func jitPathRefresh(_ paths: [String]) -> [PlanRow] {
        paths
            .map { PlanRow(name: ($0 as NSString).lastPathComponent, detail: folder($0), badge: "Gets jit's current path", toVault: false) }
    }

    /// An undo's rows, from `jit migrate undo --dry-run --format json`.
    public static func undo(_ plan: UndoReport) -> [PlanRow] {
        plan.files.map { file in
            let name = (file.path as NSString).lastPathComponent
            switch file.action {
            case "remove":
                return PlanRow(name: name, detail: folder(file.path), badge: "Removed", toVault: false)
            default:
                let names = file.secrets.map { $0.split(separator: "/").last.map(String.init) ?? $0 }
                return PlanRow(
                    name: name,
                    detail: names.isEmpty ? folder(file.path) : NameList.capped(names),
                    badge: "Back in plain text",
                    toVault: false
                )
            }
        }
    }

    private static func folder(_ path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        let home = NSHomeDirectory()
        if parent == home {
            return "~"
        }
        // With the slash: /Users/dana2 is not inside /Users/dana.
        return parent.hasPrefix(home + "/") ? "~" + parent.dropFirst(home.count) : parent
    }
}
