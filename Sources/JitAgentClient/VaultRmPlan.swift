// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// `jit vault rm --dry-run --format json <paths>` (jit 1.9+): what a delete
/// would remove and who still uses it, read before the app asks anything.
/// Prompt-free, writes nothing. The app's old warning came from the vault
/// listing's `used_by`, which saw only the global store and this directory's;
/// two MCP profiles broke because it said nothing (jitpass/jit
/// design/doctor-repair.md, "The incident"). This is the engine's own strict
/// answer: every project store under ~, every mount, every pointer file.
public struct VaultRmPlan: Decodable, Sendable, Equatable {
    /// The expanded secrets that exist: a group argument becomes its paths.
    public var paths: [String]
    /// Arguments with no secret stored behind them.
    public var missing: [String]
    /// One row per (path, user).
    public var inUse: [VaultRmUse]
    /// Whether the real run would stop without --break-profiles.
    public var refused: Bool
    /// Set when jit could not tell what uses the paths; "can't tell" is
    /// never "unused".
    public var error: String?

    enum CodingKeys: String, CodingKey {
        case paths, missing, refused, error
        case inUse = "in_use"
    }

    public init(paths: [String] = [], missing: [String] = [], inUse: [VaultRmUse] = [], refused: Bool = false, error: String? = nil) {
        self.paths = paths
        self.missing = missing
        self.inUse = inUse
        self.refused = refused
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        paths = try box.decodeIfPresent([String].self, forKey: .paths) ?? []
        missing = try box.decodeIfPresent([String].self, forKey: .missing) ?? []
        inUse = try box.decodeIfPresent([VaultRmUse].self, forKey: .inUse) ?? []
        refused = try box.decodeIfPresent(Bool.self, forKey: .refused) ?? false
        let error = try box.decodeIfPresent(String.self, forKey: .error)
        self.error = error?.isEmpty == true ? nil : error
    }

    public static func parse(_ data: Data) throws -> VaultRmPlan {
        try JSONDecoder().decode(VaultRmPlan.self, from: data)
    }

    /// The dry run for `paths`.
    public static func arguments(for paths: [String]) -> [String] {
        ["vault", "rm", "--dry-run", "--format", "json"] + paths
    }

    /// Nothing the engine can see uses the paths: the ordinary delete.
    public var isClean: Bool {
        inUse.isEmpty && error == nil && !refused
    }

    /// One entry per profile or pointer file, in the order jit names them:
    /// profiles by name, then pointer files by path.
    public var users: [VaultRmUser] {
        var byKey: [String: VaultRmUser] = [:]
        for use in inUse {
            let user = VaultRmUser(use)
            if var known = byKey[user.key] {
                if !known.paths.contains(use.path) {
                    known.paths.append(use.path)
                }
                for config in use.launchedBy where !known.launchedBy.contains(config) {
                    known.launchedBy.append(config)
                }
                for tool in use.tools where !known.tools.contains(tool) {
                    known.tools.append(tool)
                }
                byKey[user.key] = known
            } else {
                byKey[user.key] = user
            }
        }
        return byKey.keys.sorted().compactMap { byKey[$0] }
    }
}

/// One `in_use` row: a profile (with its store, project, mount and the
/// tools known to use it) or a pointer file, and the path it uses.
public struct VaultRmUse: Decodable, Sendable, Equatable {
    public var path: String
    public var profile: String?
    public var scope: String?
    public var project: String?
    public var mount: String?
    public var pointerFile: String?
    /// The configs that start the profile's tools (jit 1.9+).
    public var launchedBy: [String]
    /// The tools themselves, by name and config (jit 2.0+); empty from an
    /// older jit, which the dialog then words from `launchedBy`.
    public var tools: [VaultRmTool]

    enum CodingKeys: String, CodingKey {
        case path, profile, scope, project, mount, tools
        case pointerFile = "pointer_file"
        case launchedBy = "launched_by"
    }

    public init(
        path: String, profile: String? = nil, scope: String? = nil, project: String? = nil,
        mount: String? = nil, pointerFile: String? = nil, launchedBy: [String] = [], tools: [VaultRmTool] = []
    ) {
        self.path = path
        self.profile = profile
        self.scope = scope
        self.project = project
        self.mount = mount
        self.pointerFile = pointerFile
        self.launchedBy = launchedBy
        self.tools = tools
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        path = try box.decodeIfPresent(String.self, forKey: .path) ?? ""
        profile = try box.decodeIfPresent(String.self, forKey: .profile).flatMap { $0.isEmpty ? nil : $0 }
        scope = try box.decodeIfPresent(String.self, forKey: .scope).flatMap { $0.isEmpty ? nil : $0 }
        project = try box.decodeIfPresent(String.self, forKey: .project).flatMap { $0.isEmpty ? nil : $0 }
        mount = try box.decodeIfPresent(String.self, forKey: .mount).flatMap { $0.isEmpty ? nil : $0 }
        pointerFile = try box.decodeIfPresent(String.self, forKey: .pointerFile).flatMap { $0.isEmpty ? nil : $0 }
        launchedBy = try box.decodeIfPresent([String].self, forKey: .launchedBy) ?? []
        tools = try box.decodeIfPresent([VaultRmTool].self, forKey: .tools) ?? []
    }
}

/// A tool that uses a profile: an MCP server's name, and the config that
/// starts it.
public struct VaultRmTool: Decodable, Sendable, Equatable {
    public var name: String
    public var config: String

    public init(name: String, config: String) {
        self.name = name
        self.config = config
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.decodeIfPresent(String.self, forKey: .name) ?? ""
        config = try box.decodeIfPresent(String.self, forKey: .config) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case name, config
    }
}

/// Everything one profile or pointer file uses of the doomed set.
public struct VaultRmUser: Sendable, Equatable {
    /// The profile's name; nil for a pointer file.
    public var profile: String?
    public var scope: String?
    public var project: String?
    public var mount: String?
    public var pointerFile: String?
    public var launchedBy: [String]
    public var tools: [VaultRmTool]
    public var paths: [String]

    init(_ use: VaultRmUse) {
        profile = use.pointerFile == nil ? (use.profile ?? "?") : nil
        scope = use.scope
        project = use.project
        mount = use.mount
        pointerFile = use.pointerFile
        launchedBy = use.launchedBy
        tools = use.tools
        paths = [use.path]
    }

    var key: String {
        if let pointerFile {
            return "1\u{0}" + pointerFile
        }
        return "0\u{0}" + (profile ?? "") + "\u{0}" + (project ?? scope ?? "")
    }
}
