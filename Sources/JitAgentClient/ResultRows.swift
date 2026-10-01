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
        return parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
    }
}
