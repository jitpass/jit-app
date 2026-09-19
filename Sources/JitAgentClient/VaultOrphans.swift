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

public extension VaultOrphans {
    /// What the app runs for a prune: the listing's own paths are not
    /// passed, jit collects them again as it runs.
    static let pruneArguments = ["vault", "orphans", "--prune", "--yes"]

    /// The prune's confirmation, from a listing fetched immediately before
    /// it: the doctor report can be minutes old, and a secret that was an
    /// orphan then may be a live profile's now. Names every path (up to
    /// `limit`), the stale mount registrations it clears too, and whether
    /// Touch ID follows (clearing registrations alone asks for none).
    func pruneConfirmation(home: String = NSHomeDirectory(), limit: Int = 15) -> DeleteConfirmation {
        let secrets = orphans.count
        let mounts = staleMounts.count
        guard !isEmpty else {
            return DeleteConfirmation(
                title: "Nothing to prune",
                message: "jit finds no orphaned secret and no stale mount registration now; the earlier report was out of date.",
                button: nil, breaks: false, arguments: []
            )
        }
        let command = "This runs:\n\njit vault orphans --prune --yes\n\n"
        let mountLines = Self.capped(staleMounts.map { VaultRmPlan.short($0.mountPath, home) }, limit)
        let mountNoun = "stale mount registration" + (mounts == 1 ? "" : "s")
        guard secrets > 0 else {
            return DeleteConfirmation(
                title: "Clear \(mounts) \(mountNoun)?",
                message: command + "As of just now, it clears:\n" + mountLines
                    + "\n\nTheir projects are gone. No secret is touched and no Touch ID is asked. Nothing asks again.",
                button: "Clear", breaks: false, arguments: Self.pruneArguments
            )
        }
        let noun = "orphaned secret" + (secrets == 1 ? "" : "s")
        var message = command + "As of just now, it deletes for good:\n"
            + Self.capped(orphans.map { $0.path + ($0.origin.isEmpty ? "" : " · from " + $0.origin) }, limit)
        if mounts > 0 {
            message += "\n\nIt also clears \(mounts) \(mountNoun), whose project is gone (no secret is touched):\n" + mountLines
        }
        message += "\n\nNo profile or pointer file jit can find uses these, but a project outside your home folder "
            + "is not searched: check the origins first. Nothing asks again. Touch ID follows."
        return DeleteConfirmation(
            title: "Prune \(secrets) \(noun)" + (mounts > 0 ? " and clear \(mounts) stale mount\(mounts == 1 ? "" : "s")?" : "?"),
            message: message, button: "Prune", breaks: false, arguments: Self.pruneArguments,
            paths: orphans.map(\.path)
        )
    }

    /// One per line, the first `limit` of them and a count of the rest.
    internal static func capped(_ lines: [String], _ limit: Int) -> String {
        guard lines.count > limit else {
            return lines.joined(separator: "\n")
        }
        return lines.prefix(limit).joined(separator: "\n") + "\n…and \(lines.count - limit) more"
    }
}
