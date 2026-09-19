// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One finding `jit doctor --format json` reports. Problems are broken
/// state (a profile whose vault reference is missing or unreadable);
/// warnings are advisory (a stale mount, a backup nag). Both carry the
/// CLI's own fix advice, with the command to type in backticks.
public struct DoctorItem: Codable, Sendable, Equatable, Identifiable {
    public var kind: String
    public var scope: String?
    public var profile: String?
    public var variable: String?
    public var path: String?
    public var detail: String?
    public var action: String?
    /// How many findings before this one in the same report say exactly
    /// the same thing; never decoded, set by `numbered`. It keeps `id`
    /// unique when doctor repeats a finding word for word.
    var occurrence = 0

    enum CodingKeys: String, CodingKey {
        case kind, scope, profile, variable, path, detail, action
    }

    /// Unique within a report and the same across a recheck that finds the
    /// same thing: every field that tells two findings apart, detail
    /// included (a duplicates, wrap or service finding has no path or
    /// profile, only its sentence), then the repeat count.
    public var id: String {
        let base = [kind, scope ?? "", profile ?? "", variable ?? "", path ?? "", detail ?? ""].joined(separator: "|")
        return occurrence == 0 ? base : "\(base)#\(occurrence)"
    }

    /// The findings with `occurrence` counted, in order.
    static func numbered(_ items: [DoctorItem]) -> [DoctorItem] {
        var seen: [String: Int] = [:]
        return items.map { item in
            var item = item
            item.occurrence = 0
            let base = item.id
            item.occurrence = seen[base, default: 0]
            seen[base] = item.occurrence + 1
            return item
        }
    }

    /// What the row says: the CLI's detail, or for a profile problem the
    /// same sentence the text report prints.
    public var summary: String {
        if let detail, !detail.isEmpty {
            return detail
        }
        if let profile {
            let what = variable.map { " \($0)" } ?? ""
            return "profile \"\(profile)\":\(what) \(kind)"
        }
        return kind
    }

    /// The first backticked command in the action, the one thing to type.
    public var command: String? {
        commands.first
    }

    /// Every backticked command in the action, in order: doctor often
    /// offers two ("prune clears it, or unmount this one").
    public var commands: [String] {
        guard let action else {
            return []
        }
        let parts = action.split(separator: "`", omittingEmptySubsequences: false)
        // Odd-indexed pieces are inside backticks.
        return parts.enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }.filter { !$0.isEmpty }
    }

    /// "<file>" or "<path>" inside a command, which the user has to supply
    /// as a file before it can run; nil when the command is complete. A
    /// `<op://...>` (any `<scheme://...>`) is a reference to type, not a
    /// file to choose, so it is never one.
    public static func placeholder(in command: String) -> String? {
        angled(in: command).first { !$0.contains("://") }
    }

    /// True when the command carries a `<scheme://...>` the user has to
    /// write themselves: no panel can supply it, and run as-is the shell
    /// would read the angle bracket as a redirect.
    public static func needsReference(_ command: String) -> Bool {
        angled(in: command).contains { $0.contains("://") }
    }

    /// Every `<...>` token in the command, brackets included.
    private static func angled(in command: String) -> [String] {
        var out: [String] = []
        var rest = command[...]
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            out.append(String(rest[open ... close]))
            rest = rest[rest.index(after: close)...]
        }
        return out
    }
}

public struct DoctorTool: Codable, Sendable, Equatable {
    public var version: String
    public var build: String?
    public var signature: String?
}

public struct DoctorReport: Codable, Sendable, Equatable {
    public var ok: Bool
    public var tool: DoctorTool?
    public var profilesChecked: Int?
    public var secretsChecked: Int?
    public var problems: [DoctorItem]
    public var warnings: [DoctorItem]

    enum CodingKeys: String, CodingKey {
        case ok, tool, problems, warnings
        case profilesChecked = "profiles_checked"
        case secretsChecked = "secrets_checked"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        tool = try container.decodeIfPresent(DoctorTool.self, forKey: .tool)
        profilesChecked = try container.decodeIfPresent(Int.self, forKey: .profilesChecked)
        secretsChecked = try container.decodeIfPresent(Int.self, forKey: .secretsChecked)
        problems = try DoctorItem.numbered(container.decodeIfPresent([DoctorItem].self, forKey: .problems) ?? [])
        warnings = try DoctorItem.numbered(container.decodeIfPresent([DoctorItem].self, forKey: .warnings) ?? [])
    }

    /// Profile name to a one-line reason it cannot be granted.
    public var brokenProfiles: [String: String] {
        var out: [String: String] = [:]
        for problem in problems {
            guard let profile = problem.profile, out[profile] == nil else {
                continue
            }
            out[profile] = problem.variable.map { "\(problem.kind): \($0)" } ?? problem.kind
        }
        return out
    }

    /// The panel's one-line verdict.
    public var verdict: String {
        if problems.isEmpty, warnings.isEmpty {
            return "all good"
        }
        var parts: [String] = []
        if !problems.isEmpty {
            parts.append("\(problems.count) problem" + (problems.count == 1 ? "" : "s"))
        }
        if !warnings.isEmpty {
            parts.append("\(warningCount) warning" + (warningCount == 1 ? "" : "s"))
        }
        return parts.joined(separator: ", ")
    }
}
