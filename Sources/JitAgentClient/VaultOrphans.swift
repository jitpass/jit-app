// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// `jit vault orphans --format json`: secrets no profile jit can see
/// references, each with the origin it was migrated from, and mount
/// registrations whose profile is gone. Prompt-free; nothing is decrypted.
public struct VaultOrphans: Codable, Sendable, Equatable {
    public var count: Int
    public var orphans: [VaultOrphan]
    public var staleMounts: [VaultStaleMount]

    enum CodingKeys: String, CodingKey {
        case count, orphans
        case staleMounts = "stale_mounts"
    }

    public init(count: Int = 0, orphans: [VaultOrphan] = [], staleMounts: [VaultStaleMount] = []) {
        self.count = count
        self.orphans = orphans
        self.staleMounts = staleMounts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orphans = try container.decodeIfPresent([VaultOrphan].self, forKey: .orphans) ?? []
        staleMounts = try container.decodeIfPresent([VaultStaleMount].self, forKey: .staleMounts) ?? []
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? orphans.count
    }

    public var isEmpty: Bool {
        orphans.isEmpty && staleMounts.isEmpty
    }
}

public struct VaultOrphan: Codable, Sendable, Equatable, Identifiable {
    public var path: String
    /// The file it was migrated from, "" when none was recorded.
    public var origin: String

    public init(path: String, origin: String = "") {
        self.path = path
        self.origin = origin
    }

    public var id: String {
        path
    }
}

public struct VaultStaleMount: Codable, Sendable, Equatable, Identifiable {
    public var mountPath: String
    public var profilePath: String

    enum CodingKeys: String, CodingKey {
        case mountPath = "mount_path"
        case profilePath = "profile_path"
    }

    public init(mountPath: String, profilePath: String) {
        self.mountPath = mountPath
        self.profilePath = profilePath
    }

    public var id: String {
        mountPath
    }
}

/// Orphaned secrets grouped by project: the first path segment, the unit
/// `jit vault list` groups by, `jit vault rm` expands, and the one a reader
/// recognises. 59 paths is a table; 10 projects is a decision.
public struct VaultOrphanGroup: Identifiable, Sendable, Equatable {
    public var name: String
    public var orphans: [VaultOrphan]

    public init(name: String, orphans: [VaultOrphan]) {
        self.name = name
        self.orphans = orphans
    }

    public var id: String {
        name
    }

    public var paths: [String] {
        orphans.map(\.path)
    }

    /// The variable names inside the project, without the project prefix.
    public var keys: [String] {
        orphans.map(\.key)
    }

    /// The distinct files these secrets were migrated from; empty when jit
    /// recorded none, which is what a pre-provenance vault looks like.
    public var origins: [String] {
        var seen: [String] = []
        for origin in orphans.compactMap(\.originFile) where !seen.contains(origin) {
            seen.append(origin)
        }
        return seen
    }
}

public extension VaultOrphan {
    /// The file this secret was migrated from, when jit recorded one.
    /// `origin` is not empty when it did not: jit fills the field with a
    /// sentence ("no recorded origin (pre-provenance, or set directly)"),
    /// which is what covered every line of the old listing. The app shows
    /// an origin as a file and opens it in Finder, so only an absolute or
    /// home-relative path counts as one; anything else is jit explaining
    /// itself, and the row says "origin not recorded" instead.
    var originFile: String? {
        let trimmed = origin.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~") else {
            return nil
        }
        return trimmed
    }

    /// The variable name: everything after the project, or the whole path
    /// when there is no slash in it.
    var key: String {
        path.firstIndex(of: "/").map { String(path[path.index(after: $0)...]) } ?? path
    }
}

public extension VaultOrphans {
    /// What clearing stale mount registrations runs. jit has no command for
    /// the registrations alone: `--prune` deletes every orphaned secret in
    /// the same pass, so the app never sends this without saying so first.
    /// Orphaned secrets themselves are deleted with `jit vault rm`, which
    /// takes any subset under one gesture and refuses what is still in use.
    static let pruneArguments = ["vault", "orphans", "--prune", "--yes"]

    /// One group per project, projects in path order, secrets inside them
    /// in path order.
    var groups: [VaultOrphanGroup] {
        var order: [String] = []
        var byName: [String: [VaultOrphan]] = [:]
        for orphan in orphans.sorted(by: { $0.path < $1.path }) {
            let name = orphan.path.firstIndex(of: "/").map { String(orphan.path[..<$0]) } ?? orphan.path
            if byName[name] == nil {
                order.append(name)
            }
            byName[name, default: []].append(orphan)
        }
        return order.map { VaultOrphanGroup(name: $0, orphans: byName[$0] ?? []) }
    }

    /// The groups whose project, key or origin contains `filter`, matched
    /// the way the Vault window's own filter matches: case-insensitively,
    /// keeping only the secrets that match inside a group that does not.
    func groups(matching filter: String) -> [VaultOrphanGroup] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else {
            return groups
        }
        return groups.compactMap { group in
            if group.name.lowercased().contains(needle) {
                return group
            }
            let kept = group.orphans.filter { orphan in
                orphan.path.lowercased().contains(needle)
                    || orphan.originFile?.lowercased().contains(needle) == true
            }
            return kept.isEmpty ? nil : VaultOrphanGroup(name: group.name, orphans: kept)
        }
    }

    /// The stale mounts jit would clear, shortened to ~.
    func staleMountPaths(home: String = NSHomeDirectory()) -> [String] {
        staleMounts.map { VaultRmPlan.short($0.mountPath, home) }
    }

    /// One per line, the first `limit` of them and a count of the rest.
    /// Shared with the duplicates report, which lists paths the same way.
    internal static func capped(_ lines: [String], _ limit: Int) -> String {
        guard lines.count > limit else {
            return lines.joined(separator: "\n")
        }
        return lines.prefix(limit).joined(separator: "\n") + "\n\u{2026}and \(lines.count - limit) more"
    }

    /// The question before clearing stale mount registrations, worded from
    /// a listing taken immediately before it. The registrations alone are a
    /// registry edit that touches no secret and asks for no gesture; but
    /// `--prune` is the only command that makes it, and the same run
    /// deletes every orphaned secret still listed. When any remain, that is
    /// what the dialog leads with, and its button takes neither Return nor
    /// the count of mounts.
    func staleMountConfirmation(home: String = NSHomeDirectory()) -> DeleteConfirmation {
        let mounts = staleMounts.count
        guard mounts > 0 else {
            return DeleteConfirmation(
                title: "Nothing to clear",
                message: "jit finds no stale mount registration now; the list was out of date.",
                button: nil, breaks: false, arguments: []
            )
        }
        let noun = "stale mount registration" + (mounts == 1 ? "" : "s")
        let listed = staleMountPaths(home: home).joined(separator: "\n")
        let secrets = orphans.count
        guard secrets > 0 else {
            return DeleteConfirmation(
                title: "Clear \(mounts) \(noun)?",
                message: "jit still serves \(mounts == 1 ? "this mount" : "these mounts") for \(mounts == 1 ? "a project" : "projects") "
                    + "whose profile file is gone:\n\(listed)\n\nClearing is a registry edit: no secret is touched, "
                    + "and no Touch ID is asked.",
                button: "Clear", breaks: false, arguments: Self.pruneArguments
            )
        }
        let secretNoun = "orphaned secret" + (secrets == 1 ? "" : "s")
        return DeleteConfirmation(
            title: "Clearing \(mounts) \(noun) also deletes \(secrets) \(secretNoun)",
            message: "jit clears \(mounts == 1 ? "a registration" : "registrations") only while pruning orphans, "
                + "so the \(secrets) \(secretNoun) still in the list \(secrets == 1 ? "goes" : "go") too, for good, "
                + "with no archive and no undo.\n\nThe registrations:\n\(listed)\n\n"
                + "To keep any of those secrets, delete the rest from the list first and clear the mounts once it is empty. "
                + "Touch ID follows.",
            button: "Clear and Delete \(secrets)", breaks: true, arguments: Self.pruneArguments, paths: orphans.map(\.path)
        )
    }
}
