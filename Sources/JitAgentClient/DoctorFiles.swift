// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One line a record group states once for all its rows ("Recorded config
/// … is deleted", "Now started by …"), and the file it names, for Show in
/// Finder.
public struct DoctorFact: Equatable, Hashable, Sendable {
    public var text: String
    public var path: String?

    public init(_ text: String, path: String?) {
        self.text = text
        self.path = path
    }
}

/// Rows the window shows together, closed by one note said once for the
/// lot: a missing profile's advice is the same for every row of one tool
/// kind, so it follows them rather than repeating under each.
public struct DoctorRun: Identifiable, Equatable, Sendable {
    public var items: [DoctorItem]
    public var note: String?

    public var id: String {
        items.first?.id ?? ""
    }
}

public extension DoctorGroup {
    /// The shared facts, one per line; empty when the rows differ.
    var facts: [DoctorFact] {
        DoctorAdvice.sharedFacts(kind, items)
    }

    /// The rows in runs: missing profiles by tool kind in first-seen
    /// order, as `jit doctor` prints them, each closed by its advice; any
    /// other kind one run with no note.
    var runs: [DoctorRun] {
        guard kind == "profile_missing" else {
            return [DoctorRun(items: items, note: nil)]
        }
        var order: [String] = []
        var byKind: [String: [DoctorItem]] = [:]
        for item in items {
            let key = item.launchers?.first?.kind ?? ""
            if byKind[key] == nil {
                order.append(key)
            }
            byKind[key, default: []].append(item)
        }
        return order.map { key in
            let rows = byKind[key] ?? []
            return DoctorRun(items: rows, note: DoctorAdvice.missingProfileAdvice(rows))
        }
    }
}

public extension DoctorAdvice {
    /// jit's advice for one missing profile, singular, to the plural it
    /// prints under several of the same kind (jitpass/jit
    /// internal/cli/doctorownership.go, brokenLauncherNote). A kind whose
    /// advice reads the same for many has no entry.
    static let pluralAdvice = [
        "mint it again, or delete that [profile] block": "mint them again, or delete those [profile] blocks"
    ]

    /// What to do about a run of missing profiles of one kind, said once:
    /// the engine's per-finding advice (its action minus the first clause,
    /// what fails, which the group note already says), made plural for
    /// several rows when jit words it so. A kind the app doesn't know
    /// shows the first finding's action as it is.
    static func missingProfileAdvice(_ rows: [DoctorItem]) -> String? {
        guard let action = rows.lazy.compactMap(\.action).first(where: { !$0.isEmpty }) else {
            return nil
        }
        let clauses = action.components(separatedBy: "; ")
        var advice = clauses.count > 1 ? clauses.dropFirst().joined(separator: "; ") : action
        if rows.count > 1, let plural = pluralAdvice[advice] {
            advice = plural
        }
        return advice.prefix(1).uppercased() + advice.dropFirst()
    }

    /// The file a row names, for Show in Finder and Copy Path; nil when it
    /// names none (a vault path is not a file). A missing profile's config,
    /// then its tool's; a pointer file, never the pointed-at secret; a
    /// record or no-known-tool row's profile manifest; the config, binary,
    /// mount or origin file the other kinds report as their path.
    static func filePath(_ item: DoctorItem) -> String? {
        let path: String? = switch item.kind {
        case "profile_missing":
            item.file ?? item.launchers?.first?.file
        case "pointer_missing", "stale_pointers":
            item.file
        case "config_deleted", "config_not_recorded", "no_known_tool", "mcp", "mcp_nested", "jit_path", "jit_path_upgrade",
             "mount", "mount_stale", "install", "completion", "origin_gone":
            item.path
        default:
            nil
        }
        return path?.nilIfEmpty
    }
}

/// Where jit keeps the global profiles (jitpass/jit internal/profile): one
/// `<name>.yaml` each under ~/.jit/profiles. A manifest maps variables to
/// vault paths and holds no value.
public enum ProfileFiles {
    public static func directory(home: String = NSHomeDirectory()) -> String {
        (home as NSString).appendingPathComponent(".jit/profiles")
    }

    /// A global profile's manifest: the path the engine reported, when it
    /// did, else where jit keeps it.
    public static func manifest(_ name: String, reported: String? = nil, home: String = NSHomeDirectory()) -> String {
        if let reported, !reported.isEmpty {
            return reported
        }
        return (directory(home: home) as NSString).appendingPathComponent(name + ".yaml")
    }
}

/// A "This runs:" command as a dialog shows it. More than `inlineLimit`
/// names on one line wrap mid-name (at a hyphen, inside a path), so past
/// that they leave the line: "+ the 7 profiles listed above" when the
/// dialog lists them already, else one per line under it. Display only:
/// what runs is the argv, which this never touches.
public enum CommandText {
    public static let inlineLimit = 3

    /// `fixed` is the command without the names and without "jit";
    /// `always` moves the names off the line even when there are few.
    public static func shown(
        _ fixed: [String], names: [String], noun: (one: String, many: String), listedAbove: Bool, always: Bool = false
    ) -> String {
        let command = "jit " + fixed.joined(separator: " ")
        guard !names.isEmpty, always || names.count > inlineLimit else {
            return "jit " + (fixed + names).joined(separator: " ")
        }
        let one = names.count == 1
        if listedAbove {
            return command + "\n+ " + (one ? "the \(noun.one) listed above" : "the \(names.count) \(noun.many) listed above")
        }
        return command + "\n+ " + (one ? "this \(noun.one):" : "these \(names.count) \(noun.many):") + "\n"
            + names.joined(separator: "\n")
    }
}
