// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// `jit profile adopt --dry-run --format json <config>` (jit 2.0+): the
/// global profiles an MCP config launches but doesn't own, read before the
/// app asks. Prompt-free, writes nothing. Adopting only rewrites owner
/// records (no vault access, no Touch ID), but it changes what a later
/// `jit migrate remove` of the config's project takes, so the dialog names
/// every profile first and the run adopts exactly those.
public struct ProfileAdoptPlan: Decodable, Sendable, Equatable {
    /// The config, absolute.
    public var config: String
    /// Owner gone first, then no owner, then owned elsewhere; by name.
    public var profiles: [ProfileAdoptCandidate]

    public init(config: String, profiles: [ProfileAdoptCandidate]) {
        self.config = config
        self.profiles = profiles
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        config = try box.decodeIfPresent(String.self, forKey: .config) ?? ""
        profiles = try box.decodeIfPresent([ProfileAdoptCandidate].self, forKey: .profiles) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case config, profiles
    }

    public static func parse(_ data: Data) throws -> ProfileAdoptPlan {
        try JSONDecoder().decode(ProfileAdoptPlan.self, from: data)
    }

    /// The dry run for `config`.
    public static func arguments(for config: String) -> [String] {
        ["profile", "adopt", "--dry-run", "--format", "json", config]
    }
}

/// One profile the config would adopt.
public struct ProfileAdoptCandidate: Decodable, Sendable, Equatable {
    public var name: String
    /// owner_gone, no_owner or owned_elsewhere.
    public var status: String
    /// The recorded owners, verbatim ("file" or "file#projectDir").
    public var owners: [String]
    /// The owner strings adopting adds.
    public var adds: [String]

    public init(name: String, status: String, owners: [String] = [], adds: [String] = []) {
        self.name = name
        self.status = status
        self.owners = owners
        self.adds = adds
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.decodeIfPresent(String.self, forKey: .name) ?? ""
        status = try box.decodeIfPresent(String.self, forKey: .status) ?? ""
        owners = try box.decodeIfPresent([String].self, forKey: .owners) ?? []
        adds = try box.decodeIfPresent([String].self, forKey: .adds) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case name, status, owners, adds
    }
}

public extension ProfileAdoptPlan {
    /// The dialog for this plan. `home` shortens paths to ~; `exists` says
    /// whether an owner's file is still there, for "owned by".
    func confirmation(
        home: String = NSHomeDirectory(), exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> DeleteConfirmation {
        let shown = VaultRmPlan.short(config, home)
        guard !profiles.isEmpty else {
            return DeleteConfirmation(
                title: "Nothing to adopt", message: "\(shown) already owns every profile it launches.",
                button: nil, breaks: false, arguments: [], destructive: false
            )
        }
        let names = profiles.map(\.name)
        let one = profiles.count == 1
        let rows = profiles.map { "• \($0.name) · \(label($0, home: home, exists: exists))" }
        var parts = ["\(shown) launches \(one ? "this profile" : "these") but doesn't own \(one ? "it" : "them"):\n"
            + rows.joined(separator: "\n")]
        var owning = "Adopting records \(shown) as \(one ? "its" : "their") owner"
        if let clause = migrateRemoveClause(home: home) {
            owning += ", so \(clause)"
        }
        parts.append(owning + ".")
        let arguments = ["profile", "adopt", "--yes", config] + names
        parts.append("This runs:\n\njit " + (["profile", "adopt", "--yes", shown] + names).joined(separator: " ")
            + "\n\nIt changes owner records only: no secret is read or changed, and nothing asks again.")
        return DeleteConfirmation(
            title: one ? "Adopt \(names[0])?" : "Adopt \(names.count) profiles?", message: parts.joined(separator: "\n\n"),
            button: one ? "Adopt" : "Adopt \(names.count)", breaks: false, arguments: arguments, destructive: false
        )
    }

    /// jit's status column: "owner gone", "no owner", "owned by <file>".
    private func label(_ candidate: ProfileAdoptCandidate, home: String, exists: (String) -> Bool) -> String {
        switch candidate.status {
        case "owner_gone": return "owner gone"
        case "no_owner": return "no owner"
        default: break
        }
        let live = candidate.owners.filter { exists(DoctorAdvice.ownerFile($0)) }
        let other = live.first { DoctorAdvice.ownerFile($0) != config } ?? live.first
        guard let other else {
            return candidate.status.replacingOccurrences(of: "_", with: " ")
        }
        let file = VaultRmPlan.short(DoctorAdvice.ownerFile(other), home)
        let scope = other.firstIndex(of: "#").map { " (" + VaultRmPlan.short(String(other[other.index(after: $0)...]), home) + ")" }
        return "owned by " + file + (scope ?? "")
    }

    /// "jit migrate remove ~/proj will then take them too", when the
    /// engine's text would say it: the config sits in a project directory
    /// (not home, not an app's folder under ~/Library or a ~/.dir), and at
    /// least one profile has no other live owner. `jit migrate remove`
    /// goes by the first owner, so a profile owned elsewhere stays.
    func migrateRemoveClause(home: String) -> String? {
        guard let dir = Self.migrateRemoveTarget(config, home: home) else {
            return nil
        }
        let unowned = profiles.filter { $0.status != "owned_elsewhere" }
        guard !unowned.isEmpty else {
            return nil
        }
        let shown = VaultRmPlan.short(dir, home)
        let what = if unowned.count == profiles.count {
            profiles.count == 1 ? "it" : "them"
        } else {
            "the \(unowned.count) with no other owner"
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
