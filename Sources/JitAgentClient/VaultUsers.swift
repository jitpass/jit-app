// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One thing using a vault secret, as `jit vault list --users` finds it
/// (jit 2.3.3): a profile and the project folder it lives in (nil for the
/// global store), or a pointer file. Found anywhere under home, unlike
/// `used_by`, which sees only the current folder and the global store.
public struct VaultSecretUser: Codable, Sendable, Equatable, Hashable {
    public var profile: String?
    public var project: String?
    public var pointerFile: String?

    public init(profile: String? = nil, project: String? = nil, pointerFile: String? = nil) {
        self.profile = profile
        self.project = project
        self.pointerFile = pointerFile
    }

    enum CodingKeys: String, CodingKey {
        case profile, project
        case pointerFile = "pointer_file"
    }
}

/// Just the `users` of a `--users` listing, by vault path: what the window
/// keeps between the quick listings every action reloads.
public struct VaultUsersListing: Decodable, Sendable, Equatable {
    public var byPath: [String: [VaultSecretUser]]

    struct Row: Decodable {
        var path: String
        var users: [VaultSecretUser]?
    }

    enum CodingKeys: String, CodingKey {
        case secrets
    }

    public init(byPath: [String: [VaultSecretUser]]) {
        self.byPath = byPath
    }

    public init(from decoder: Decoder) throws {
        let rows = try decoder.container(keyedBy: CodingKeys.self).decode([Row].self, forKey: .secrets)
        byPath = Dictionary(rows.map { ($0.path, $0.users ?? []) }, uniquingKeysWith: { first, _ in first })
    }

    /// The profiles using any of a profile's secrets, once each, in order.
    public func profiles(for paths: [String]) -> [VaultSecretUser] {
        var out: [VaultSecretUser] = []
        for path in paths {
            for user in byPath[path] ?? [] where user.profile != nil && !out.contains(user) {
                out.append(user)
            }
        }
        return out
    }
}
