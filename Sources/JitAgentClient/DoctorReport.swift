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
    /// origin_gone's structured half (schema 2): every vault group born
    /// from the gone file, and every profile that still names one of their
    /// secrets.
    public var groups: [String]?
    public var profiles: [String]?
    /// The action's commands as data (schema 2): argv, and whether each
    /// deletes something or asks for Touch ID. Nil from an older jit, whose
    /// commands are recovered from the action's backticks instead; in a
    /// schema 2 report an absent list means the action names none.
    public var fixes: [DoctorFix]?
    /// The ownership kinds' structured half (jit 2.0: launcher_broken,
    /// pointer_missing, owner_gone, no_owner, unlaunched). `file` is the
    /// launcher or pointer file; `config` the MCP config doctor's adopt
    /// command names, `configs` every config that launches the profile;
    /// `owners` the recorded owners; `secrets` and `secretsMissing` an
    /// unlaunched profile's counts; `origin` the file it was made from,
    /// when that is gone.
    public var file: String?
    public var config: String?
    public var configs: [String]?
    public var owners: [String]?
    public var launchers: [DoctorLauncher]?
    public var secrets: Int?
    public var secretsMissing: Int?
    public var origin: String?
    /// How many findings before this one in the same report say exactly
    /// the same thing; never decoded, set by `numbered`. It keeps `id`
    /// unique when doctor repeats a finding word for word.
    var occurrence = 0

    enum CodingKeys: String, CodingKey {
        case kind, scope, profile, variable, path, detail, action, groups, profiles, fixes
        case file, config, configs, owners, launchers, secrets, origin
        case secretsMissing = "secrets_missing"
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

    /// Every command in the action, in order: doctor often offers two
    /// ("prune clears it, or unmount this one"). The engine's own `fixes`
    /// when the report has them, else the backticked spans.
    public var commands: [String] {
        if let fixes {
            return fixes.map(\.command).filter { !$0.isEmpty }
        }
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

/// One command from a finding's action, as the engine classifies it
/// (jitpass/jit internal/cli/doctorfixes.go). `argv` omits a jit command's
/// leading "jit"; an `external` one (brew, sudo, a shell append) starts
/// with its program and may hold shell syntax, so it is shown or run in a
/// shell, never exec'd.
public struct DoctorFix: Codable, Sendable, Equatable {
    public var command: String
    public var argv: [String]
    public var external: Bool
    /// Running it deletes something or takes a protection away. Absent
    /// counts as true: a fix the engine did not classify is destructive.
    public var destructive: Bool
    /// It asks for a fresh Touch ID or passcode itself.
    public var presence: Bool
    /// The placeholder the caller fills before it runs (`<file>`), as it
    /// appears in `argv`; nil when the command is complete.
    public var needs: String?

    public init(
        command: String, argv: [String] = [], external: Bool = false, destructive: Bool = true,
        presence: Bool = false, needs: String? = nil
    ) {
        self.command = command
        self.argv = argv
        self.external = external
        self.destructive = destructive
        self.presence = presence
        self.needs = needs
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        command = try box.decodeIfPresent(String.self, forKey: .command) ?? ""
        argv = try box.decodeIfPresent([String].self, forKey: .argv) ?? []
        external = try box.decodeIfPresent(Bool.self, forKey: .external) ?? false
        destructive = try box.decodeIfPresent(Bool.self, forKey: .destructive) ?? true
        presence = try box.decodeIfPresent(Bool.self, forKey: .presence) ?? false
        let needs = try box.decodeIfPresent(String.self, forKey: .needs)
        self.needs = needs?.isEmpty == true ? nil : needs
    }
}

/// One thing that starts a profile or reads a secret, as the engine's
/// launcher map names it (jitpass/jit internal/launchers): its kind (mcp,
/// aws, kube, wrap, mount, shellrc, helper), the file, and the place inside
/// it ("[profile dev]", an MCP server's name, a line).
public struct DoctorLauncher: Codable, Sendable, Equatable {
    public var kind: String
    public var file: String
    public var detail: String?
    public var profile: String?
    public var vaultPath: String?
    /// Which `jit run` layer of a nested MCP entry; 0 is the outer one.
    public var layer: Int?

    enum CodingKeys: String, CodingKey {
        case kind, file, detail, profile, layer
        case vaultPath = "vault_path"
    }

    public init(kind: String, file: String, detail: String? = nil, profile: String? = nil) {
        self.kind = kind
        self.file = file
        self.detail = detail
        self.profile = profile
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        kind = try box.decodeIfPresent(String.self, forKey: .kind) ?? ""
        file = try box.decodeIfPresent(String.self, forKey: .file) ?? ""
        detail = try box.decodeIfPresent(String.self, forKey: .detail).flatMap { $0.isEmpty ? nil : $0 }
        profile = try box.decodeIfPresent(String.self, forKey: .profile).flatMap { $0.isEmpty ? nil : $0 }
        vaultPath = try box.decodeIfPresent(String.self, forKey: .vaultPath).flatMap { $0.isEmpty ? nil : $0 }
        layer = try box.decodeIfPresent(Int.self, forKey: .layer)
    }
}

public struct DoctorTool: Codable, Sendable, Equatable {
    public var version: String
    public var build: String?
    public var signature: String?
}

public struct DoctorReport: Codable, Sendable, Equatable {
    /// 1 or absent from a jit before 1.9; 2 adds `fixes`, `groups` and
    /// `profiles`.
    public var schemaVersion: Int?
    public var ok: Bool
    public var tool: DoctorTool?
    public var profilesChecked: Int?
    public var secretsChecked: Int?
    public var problems: [DoctorItem]
    public var warnings: [DoctorItem]

    enum CodingKeys: String, CodingKey {
        case ok, tool, problems, warnings
        case schemaVersion = "schema_version"
        case profilesChecked = "profiles_checked"
        case secretsChecked = "secrets_checked"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        tool = try container.decodeIfPresent(DoctorTool.self, forKey: .tool)
        profilesChecked = try container.decodeIfPresent(Int.self, forKey: .profilesChecked)
        secretsChecked = try container.decodeIfPresent(Int.self, forKey: .secretsChecked)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        let structured = (schemaVersion ?? 1) >= 2
        problems = try Self.prepared(container.decodeIfPresent([DoctorItem].self, forKey: .problems) ?? [], structured)
        warnings = try Self.prepared(container.decodeIfPresent([DoctorItem].self, forKey: .warnings) ?? [], structured)
    }

    /// Numbered; and in a schema 2 report, a finding without `fixes` gets
    /// an empty list, because there the engine fills them for every action
    /// that names a command: re-parsing backticks would resurrect exactly
    /// the commands it chose not to offer (origin_gone's note).
    private static func prepared(_ items: [DoctorItem], _ structured: Bool) -> [DoctorItem] {
        DoctorItem.numbered(items).map { item in
            var item = item
            if structured, item.fixes == nil {
                item.fixes = []
            }
            return item
        }
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
