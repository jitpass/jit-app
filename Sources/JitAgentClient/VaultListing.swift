// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One record of `jit vault list --format json`: a path and its envelope
/// header. Never a value; `list` reads headers only and never prompts,
/// which is what lets the Vault window refresh after every operation.
public struct VaultSecret: Codable, Sendable, Equatable, Identifiable {
    public var path: String
    public var version: Int
    public var secretClass: String?
    public var groupID: String?
    public var origin: String?
    /// "op-ref" for a 1Password link; absent for a stored value.
    public var storage: String?
    public var originSeenUnix: Int64?
    public var expiresUnix: Int64?
    public var createdUnix: Int64?
    public var updatedUnix: Int64?

    enum CodingKeys: String, CodingKey {
        case path
        case version
        case secretClass = "class"
        case groupID = "group_id"
        case origin
        case storage
        case originSeenUnix = "origin_seen_unix"
        case expiresUnix = "expires_unix"
        case createdUnix = "created_unix"
        case updatedUnix = "updated_unix"
    }

    public init(
        path: String,
        version: Int = 0,
        secretClass: String? = nil,
        origin: String? = nil,
        storage: String? = nil,
        updatedUnix: Int64? = nil
    ) {
        self.path = path
        self.version = version
        self.secretClass = secretClass
        self.origin = origin
        self.storage = storage
        self.updatedUnix = updatedUnix
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        secretClass = try container.decodeIfPresent(String.self, forKey: .secretClass)
        groupID = try container.decodeIfPresent(String.self, forKey: .groupID)
        origin = try container.decodeIfPresent(String.self, forKey: .origin)
        storage = try container.decodeIfPresent(String.self, forKey: .storage)
        originSeenUnix = try container.decodeIfPresent(Int64.self, forKey: .originSeenUnix)
        expiresUnix = try container.decodeIfPresent(Int64.self, forKey: .expiresUnix)
        createdUnix = try container.decodeIfPresent(Int64.self, forKey: .createdUnix)
        updatedUnix = try container.decodeIfPresent(Int64.self, forKey: .updatedUnix)
    }

    public var id: String {
        path
    }

    /// The part before the first slash, the unit `jit vault list` groups by
    /// and `jit vault rm <group>` deletes by. A path with no slash is its
    /// own group.
    public var group: String {
        path.split(separator: "/", maxSplits: 1).first.map(String.init) ?? path
    }

    /// The rest of the path, or the whole of it when there is no slash.
    public var name: String {
        let parts = path.split(separator: "/", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : path
    }

    public var isLinked: Bool {
        storage == "op-ref"
    }

    /// Version-1 envelopes predate timestamps; nil rather than 1970.
    public var updated: Date? {
        (updatedUnix ?? 0) > 0 ? Date(timeIntervalSince1970: TimeInterval(updatedUnix ?? 0)) : nil
    }
}

/// Secrets sharing a first path segment, as the CLI lists them.
public struct VaultGroup: Sendable, Equatable, Identifiable {
    public var name: String
    public var secrets: [VaultSecret]

    public var id: String {
        name
    }

    /// Whether any member is a 1Password link.
    public var hasLink: Bool {
        secrets.contains(where: \.isLinked)
    }

    /// The origin file every member was migrated from, when they agree;
    /// nil for hand-set secrets and for a group assembled from several files.
    public var origin: String? {
        let origins = Set(secrets.compactMap(\.origin))
        return origins.count == 1 ? origins.first : nil
    }
}

public struct VaultListing: Codable, Sendable, Equatable {
    public var secrets: [VaultSecret]
    /// `_backups/...` entries `jit migrate` keeps for undo; listed with
    /// `--all`, counted here, never shown as secrets.
    public var backups: [String]

    public init(secrets: [VaultSecret], backups: [String] = []) {
        self.secrets = secrets
        self.backups = backups
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        secrets = try container.decodeIfPresent([VaultSecret].self, forKey: .secrets) ?? []
        backups = try container.decodeIfPresent([String].self, forKey: .backups) ?? []
    }

    public var linkedCount: Int {
        secrets.filter(\.isLinked).count
    }

    /// Groups sorted by name, members sorted by name within each.
    public var groups: [VaultGroup] {
        let byGroup = Dictionary(grouping: secrets, by: \.group)
        return byGroup.keys.sorted().map { name in
            VaultGroup(name: name, secrets: byGroup[name]!.sorted { $0.name < $1.name })
        }
    }

    /// The groups whose name, a member's name, or an origin contains
    /// `filter`, each reduced to the members that match; the whole group
    /// when its name or origin matched. "linked" or "1password" finds the
    /// 1Password links, which have nothing else in their name to find them
    /// by. Empty filter returns everything.
    public func groups(matching filter: String) -> [VaultGroup] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else {
            return groups
        }
        let wantsLinks = "linked".hasPrefix(needle) || "1password".hasPrefix(needle)
        return groups.compactMap { group in
            if group.name.lowercased().contains(needle) || (group.origin ?? "").lowercased().contains(needle) {
                return group
            }
            let members = group.secrets.filter {
                $0.name.lowercased().contains(needle) || ($0.origin ?? "").lowercased().contains(needle)
                    || (wantsLinks && $0.isLinked)
            }
            return members.isEmpty ? nil : VaultGroup(name: group.name, secrets: members)
        }
    }
}

/// `jit vault history --format json`: the archived versions an overwrite
/// left behind, newest first. Prompt-free; nothing is decrypted.
public struct VaultHistory: Codable, Sendable, Equatable {
    public var path: String
    public var versions: [VaultVersion]

    public init(path: String, versions: [VaultVersion]) {
        self.path = path
        self.versions = versions
    }
}

public struct VaultVersion: Codable, Sendable, Equatable, Identifiable {
    /// The archive stamp `jit vault restore --version` takes.
    public var stamp: Int64
    public var createdUnix: Int64?
    public var updatedUnix: Int64?

    enum CodingKeys: String, CodingKey {
        case stamp
        case createdUnix = "created_unix"
        case updatedUnix = "updated_unix"
    }

    public init(stamp: Int64, createdUnix: Int64? = nil, updatedUnix: Int64? = nil) {
        self.stamp = stamp
        self.createdUnix = createdUnix
        self.updatedUnix = updatedUnix
    }

    public var id: Int64 {
        stamp
    }

    /// When the version was archived: the stamp is that moment in seconds.
    public var archived: Date {
        Date(timeIntervalSince1970: TimeInterval(stamp))
    }

    /// When the archived value itself was last set, if the envelope knew.
    public var valueFrom: Date? {
        (updatedUnix ?? 0) > 0 ? Date(timeIntervalSince1970: TimeInterval(updatedUnix ?? 0)) : nil
    }
}
