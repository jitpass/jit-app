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
