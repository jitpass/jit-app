// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// `jit profile attach --dry-run --format json <config>` (jit 2.0+): the
/// global profiles an MCP config uses but that don't record it, read
/// before the app asks. Prompt-free, writes nothing. Attaching only
/// rewrites which configs the profiles record (no vault access, no Touch
/// ID), but it changes what a later `jit migrate remove` of the config's
/// project takes, so the dialog names every profile first and the run
/// attaches exactly those.
public struct ProfileAttachPlan: Decodable, Sendable, Equatable {
    /// The config, absolute.
    public var config: String
    /// Recording a deleted config first, then recording none, then
    /// recording another; by name.
    public var profiles: [ProfileAttachCandidate]

    public init(config: String, profiles: [ProfileAttachCandidate]) {
        self.config = config
        self.profiles = profiles
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        config = try box.decodeIfPresent(String.self, forKey: .config) ?? ""
        profiles = try box.decodeIfPresent([ProfileAttachCandidate].self, forKey: .profiles) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case config, profiles
    }

    public static func parse(_ data: Data) throws -> ProfileAttachPlan {
        try JSONDecoder().decode(ProfileAttachPlan.self, from: data)
    }

    /// The dry run for `config`.
    public static func arguments(for config: String) -> [String] {
        ["profile", "attach", "--dry-run", "--format", "json", config]
    }
}

/// One profile attaching the config would change.
public struct ProfileAttachCandidate: Decodable, Sendable, Equatable {
    public var name: String
    /// config_deleted, no_config or recorded_elsewhere.
    public var status: String
    /// The configs its record names, verbatim ("file" or
    /// "file#projectDir"); the engine's JSON keeps the name `owners`.
    public var owners: [String]
    /// The record entries attaching adds.
    public var adds: [String]

    /// The statuses a pre-release jit 2.0 named differently, old to new.
    static let renamedStatuses = [
        "owner_gone": "config_deleted",
        "no_owner": "no_config",
        "owned_elsewhere": "recorded_elsewhere"
    ]

    public init(name: String, status: String, owners: [String] = [], adds: [String] = []) {
        self.name = name
        self.status = status
        self.owners = owners
        self.adds = adds
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.decodeIfPresent(String.self, forKey: .name) ?? ""
        let status = try box.decodeIfPresent(String.self, forKey: .status) ?? ""
        self.status = Self.renamedStatuses[status] ?? status
        owners = try box.decodeIfPresent([String].self, forKey: .owners) ?? []
        adds = try box.decodeIfPresent([String].self, forKey: .adds) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case name, status, owners, adds
    }
}

public extension ProfileAttachPlan {
    /// The dialog for this plan. `home` shortens paths to ~; `exists` says
    /// whether a recorded config is still there, for "records <file>".
    func confirmation(
        home: String = NSHomeDirectory(), exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> DeleteConfirmation {
        let shown = VaultRmPlan.short(config, home)
        guard !profiles.isEmpty else {
            return DeleteConfirmation(
                title: "Nothing to attach", message: "Every profile \(shown) uses records it already.",
                button: nil, breaks: false, arguments: [], destructive: false
            )
        }
        let names = profiles.map(\.name)
        let one = profiles.count == 1
        let rows = profiles.map { "• \($0.name) · \(label($0, home: home, exists: exists))" }
        var parts = ["\(shown) uses \(one ? "this profile, which doesn't" : "these, but they don't") record it:\n"
            + rows.joined(separator: "\n")]
        var recording = "Attaching records \(shown)"
        if let clause = migrateRemoveClause(home: home) {
            recording += ", so \(clause)"
        }
        parts.append(recording + ".")
        let arguments = ["profile", "attach", "--yes", config] + names
        // The names are listed above; on the command line they wrapped at
        // their hyphens. The argv still carries every one.
        let command = CommandText.shown(
            ["profile", "attach", "--yes", shown], names: names, noun: ("profile", "profiles"), listedAbove: true, always: true
        )
        parts.append("This runs:\n\n" + command + "\n\nIt changes which configs the "
            + (one ? "profile records" : "profiles record") + ": no secret is read or changed, and nothing asks again.")
        let target = DoctorAdvice.configShortName(config, home: home)
        return DeleteConfirmation(
            title: one ? "Record \(target) on \(names[0])?" : "Record \(target) on \(names.count) profiles?",
            message: parts.joined(separator: "\n\n"),
            button: one ? "Attach" : "Attach \(names.count)", breaks: false, arguments: arguments, destructive: false
        )
    }

    /// jit's status column: "records a deleted config", "records no
    /// config", "records <file>".
    private func label(_ candidate: ProfileAttachCandidate, home: String, exists: (String) -> Bool) -> String {
        switch candidate.status {
        case "config_deleted": return "records a deleted config"
        case "no_config": return "records no config"
        default: break
        }
        let live = candidate.owners.filter { exists(DoctorAdvice.recordedFile($0)) }
        let other = live.first { DoctorAdvice.recordedFile($0) != config } ?? live.first
        guard let other else {
            return candidate.status == "recorded_elsewhere"
                ? "records another config" : candidate.status.replacingOccurrences(of: "_", with: " ")
        }
        let file = VaultRmPlan.short(DoctorAdvice.recordedFile(other), home)
        let scope = other.firstIndex(of: "#").map { " (" + VaultRmPlan.short(String(other[other.index(after: $0)...]), home) + ")" }
        return "records " + file + (scope ?? "")
    }

    /// "jit migrate remove ~/proj will then take them too", when the
    /// engine's text would say it: the config sits in a project directory
    /// (not home, not an app's folder under ~/Library or a ~/.dir), and at
    /// least one profile records no other live config. `jit migrate
    /// remove` goes by the first recorded config, so a profile recording
    /// another stays.
    func migrateRemoveClause(home: String) -> String? {
        guard let dir = Self.migrateRemoveTarget(config, home: home) else {
            return nil
        }
        let unrecorded = profiles.filter { $0.status != "recorded_elsewhere" }
        guard !unrecorded.isEmpty else {
            return nil
        }
        let shown = VaultRmPlan.short(dir, home)
        let what = if unrecorded.count == profiles.count {
            profiles.count == 1 ? "it" : "them"
        } else {
            "the \(unrecorded.count) that record no other config"
        }
        return "jit migrate remove \(shown) will then take \(what) too"
    }

    /// The directory `jit migrate remove` would be pointed at for config's
    /// profiles (jitpass/jit profile.go, migrateRemoveTargetFor).
    static func migrateRemoveTarget(_ config: String, home: String) -> String? {
        let dir = (config as NSString).deletingLastPathComponent
        let canonicalDir = canonical(dir)
        let canonicalHome = canonical(home)
        if canonicalDir == canonicalHome {
            return nil
        }
        if canonicalDir.hasPrefix(canonicalHome + "/") {
            let first = canonicalDir.dropFirst(canonicalHome.count + 1).split(separator: "/").first.map(String.init) ?? ""
            if first == "Library" || first.hasPrefix(".") {
                return nil
            }
        }
        return dir
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

public extension DeleteConfirmation {
    /// When a `jit profile` dry run failed: a jit older than 2.0 (no
    /// `jit profile` at all), or one that printed no plan. Nothing runs.
    static func profileUnavailable(_ title: String, command: String, reason: String) -> DeleteConfirmation {
        var message = "Nothing was changed. Before it runs \(command), JitPass asks jit what it would do, and jit did not answer:\n\n"
            + (reason.isEmpty ? "(no output)" : reason)
        if reason.contains("unknown flag") || reason.contains("unknown command") || reason.contains("--dry-run") {
            message += "\n\nThat jit is older than 2.0, the first with jit profile. Update it."
        }
        return DeleteConfirmation(title: title, message: message, button: nil, breaks: false, arguments: [])
    }
}
