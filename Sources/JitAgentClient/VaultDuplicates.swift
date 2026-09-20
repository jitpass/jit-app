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
    /// Never a copy jit says is in use, even from a report that marked it
    /// prunable as well.
    public var prunablePaths: [String] {
        findings.filter { $0.prunable && $0.inUseGroup == nil }.flatMap(\.removePaths)
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
    /// Parallel to `groups`: true where that copy's origin file is gone.
    public var originGone: [Bool]
    /// jit 1.9: the copy that looks stale is still used by a profile or
    /// pointer file no command would retire with it, so jit offers no
    /// removal at all; these name who.
    public var inUseGroup: String?
    public var inUseProfiles: [String]
    public var inUsePointerFiles: [String]

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
        case originGone = "origin_gone"
        case inUseGroup = "in_use_group"
        case inUseProfiles = "in_use_profiles"
        case inUsePointerFiles = "in_use_pointer_files"
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
        originGone = try box.decodeIfPresent([Bool].self, forKey: .originGone) ?? []
        inUseGroup = try box.decodeIfPresent(String.self, forKey: .inUseGroup).flatMap { $0.isEmpty ? nil : $0 }
        inUseProfiles = try box.decodeIfPresent([String].self, forKey: .inUseProfiles) ?? []
        inUsePointerFiles = try box.decodeIfPresent([String].self, forKey: .inUsePointerFiles) ?? []
    }

    /// Whether the copy at `index` in `groups` lost its origin file.
    public func originIsGone(_ index: Int) -> Bool {
        index < originGone.count && originGone[index]
    }

    /// Who keeps the stale-looking copy alive: "profile a", "profiles a, b",
    /// then any pointer files. Empty when nothing was named.
    public var inUseBy: String {
        var parts: [String] = []
        if !inUseProfiles.isEmpty {
            parts.append((inUseProfiles.count == 1 ? "profile " : "profiles ") + inUseProfiles.joined(separator: ", "))
        }
        parts += inUsePointerFiles
        return parts.joined(separator: " and ")
    }

    public var id: String {
        groups.joined(separator: "+")
    }

    /// The groups as the sheet heads them, a copy whose origin file is gone
    /// marked so, as `jit vault duplicates` prints "(gone)".
    public var groupLabels: [String] {
        groups.enumerated().map { originIsGone($0.offset) ? $0.element + " (origin gone)" : $0.element }
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
        if let group = inUseGroup {
            let who = inUseBy.isEmpty ? "something jit found" : inUseBy
            return "same values · \(group) looks stale, but is in use by \(who) · deleting it would break that, so nothing to remove"
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

public extension VaultDuplicates {
    static let pruneArguments = ["vault", "duplicates", "--prune", "--yes"]

    /// The prune's confirmation, from a comparison run immediately before
    /// it. jit compares again as it prunes and deletes what it finds then;
    /// this names what it found a moment ago.
    func pruneConfirmation(limit: Int = 15) -> DeleteConfirmation {
        let paths = prunablePaths
        guard !paths.isEmpty else {
            return DeleteConfirmation(
                title: "Nothing to prune",
                message: "Compared again just now: no stale copy is both origin-less and unused any more.",
                button: nil, breaks: false, arguments: []
            )
        }
        let noun = "stale secret" + (paths.count == 1 ? "" : "s")
        return DeleteConfirmation(
            title: "Prune \(paths.count) \(noun)?",
            message: "As of the comparison just now, it deletes for good:\n"
                + VaultOrphans.capped(paths, limit)
                + "\n\nEach is a copy whose origin file is gone and which no profile or pointer file jit can find uses. "
                + "Every other finding keeps its printed command. Touch ID follows, once per class again.",
            button: "Prune", breaks: false, arguments: Self.pruneArguments, paths: paths
        )
    }
}
