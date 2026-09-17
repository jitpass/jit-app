// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// `jit vault duplicates --format json`: groups holding the same key set
/// from the same file, with whether the values agree and the one command
/// that retires the stale copy correctly. Reading it decrypts every
/// secret, so it costs an unlock and one consent per gated class.
public struct VaultDuplicates: Codable, Sendable, Equatable {
    public var findings: [VaultDuplicate]
    public var sharedCredentials: [VaultSharedCredential]
    public var secretsCompared: Int

    enum CodingKeys: String, CodingKey {
        case findings
        case sharedCredentials = "shared_credentials"
        case secretsCompared = "secrets_compared"
    }

    public init(findings: [VaultDuplicate] = [], sharedCredentials: [VaultSharedCredential] = [], secretsCompared: Int = 0) {
        self.findings = findings
        self.sharedCredentials = sharedCredentials
        self.secretsCompared = secretsCompared
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        findings = try container.decodeIfPresent([VaultDuplicate].self, forKey: .findings) ?? []
        sharedCredentials = try container.decodeIfPresent([VaultSharedCredential].self, forKey: .sharedCredentials) ?? []
        secretsCompared = try container.decodeIfPresent(Int.self, forKey: .secretsCompared) ?? 0
    }

    /// What `--prune` would delete: every prunable finding's stale paths.
    public var prunablePaths: [String] {
        findings.filter(\.prunable).flatMap(\.removePaths)
    }
}

public struct VaultDuplicate: Codable, Sendable, Equatable, Identifiable {
    public var groups: [String]
    public var keys: [String]
    public var origins: [String]
    public var sameOrigin: Bool
    public var valuesMatch: Bool
    public var removeGroup: String?
    public var removeCommand: String?
    public var prunable: Bool
    public var removePaths: [String]
    public var differKeys: [String]
    public var extraKeys: [String]
    public var alsoRemoves: [String]
    public var removeBlockedBy: String?

    enum CodingKeys: String, CodingKey {
        case groups, keys, origins, prunable
        case sameOrigin = "same_origin"
        case valuesMatch = "values_match"
        case removeGroup = "remove_group"
        case removeCommand = "remove_command"
        case removePaths = "remove_paths"
        case differKeys = "differ_keys"
        case extraKeys = "extra_keys"
        case alsoRemoves = "also_removes"
        case removeBlockedBy = "remove_blocked_by"
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        groups = try box.decodeIfPresent([String].self, forKey: .groups) ?? []
        keys = try box.decodeIfPresent([String].self, forKey: .keys) ?? []
        origins = try box.decodeIfPresent([String].self, forKey: .origins) ?? []
        sameOrigin = try box.decodeIfPresent(Bool.self, forKey: .sameOrigin) ?? false
        valuesMatch = try box.decodeIfPresent(Bool.self, forKey: .valuesMatch) ?? false
        removeGroup = try box.decodeIfPresent(String.self, forKey: .removeGroup)
        removeCommand = try box.decodeIfPresent(String.self, forKey: .removeCommand)
        prunable = try box.decodeIfPresent(Bool.self, forKey: .prunable) ?? false
        removePaths = try box.decodeIfPresent([String].self, forKey: .removePaths) ?? []
        differKeys = try box.decodeIfPresent([String].self, forKey: .differKeys) ?? []
        extraKeys = try box.decodeIfPresent([String].self, forKey: .extraKeys) ?? []
        alsoRemoves = try box.decodeIfPresent([String].self, forKey: .alsoRemoves) ?? []
        removeBlockedBy = try box.decodeIfPresent(String.self, forKey: .removeBlockedBy)
    }

    public var id: String {
        groups.joined(separator: "+")
    }

    /// One line, the CLI's verdict in the app's words.
    public var verdict: String {
        if !valuesMatch {
            let which = differKeys.isEmpty ? "" : " (" + differKeys.joined(separator: ", ") + ")"
            return "values differ\(which) · your call, nothing to remove"
        }
        if !extraKeys.isEmpty {
            return "same values, but " + extraKeys.joined(separator: ", ") + " only in some copies · nothing removed"
        }
        if let blocked = removeBlockedBy {
            return "same values · removing would also take \(blocked), so no command"
        }
        if prunable, let group = removeGroup {
            return "same values · \(group) is a stale copy, origin gone, nothing references it · Prune deletes it"
        }
        if let group = removeGroup {
            let also = alsoRemoves.isEmpty ? "" : " (also un-migrates " + alsoRemoves.joined(separator: ", ") + ")"
            return "same values · retire \(group)\(also)"
        }
        return "same values"
    }
}

/// The same value under the same key names from independent files: not a
/// problem, listed so a rotation reaches every place.
public struct VaultSharedCredential: Codable, Sendable, Equatable, Identifiable {
    public var keys: [String]
    public var groups: [String]

    public var id: String {
        groups.joined(separator: "+") + ":" + keys.joined(separator: ",")
    }
}
