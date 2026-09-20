// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A row about a file, in the three things a reader needs: which file,
/// where it is, and what is true of it.
public struct RowParts: Equatable, Sendable {
    public var name: String
    public var folder: String
    public var fact: String
}

/// How a finding READS as one row — its text, and whether that text is a
/// path. Separate from DoctorAdvice's button building, which answers the
/// different question of what the row lets you DO about it.
public extension DoctorAdvice {
    /// What the row says. The group title and note already say what the
    /// kind means, so a row repeats none of it: a mount row is its path, an
    /// origin row is the secrets and the file they came from, a profile
    /// row is the profile and the variable. Anything else is doctor's own
    /// sentence.
    static func rowText(_ item: DoctorItem) -> String {
        switch item.kind {
        case "mount", "mount_stale", "install", "completion", "jit_path", "jit_path_upgrade", "1password_link":
            return item.path.map(homePath) ?? item.summary
        case "origin_gone":
            return originRow(item)
        case _ where ownershipKinds.contains(item.kind):
            return ownershipRow(item)
        default:
            if let profile = item.profile, let variable = item.variable, item.detail?.isEmpty ?? true {
                return "\(profile) · \(variable)"
            }
            return item.summary
        }
    }

    /// Rows that are a path read best in monospace, truncated at the start.
    static func rowIsPath(_ item: DoctorItem) -> Bool {
        switch item.kind {
        case "mount", "mount_stale", "install", "completion", "jit_path", "jit_path_upgrade", "1password_link":
            item.path != nil
        case "origin_gone", "missing", "corrupt", "bad_path":
            true
        case "pointer_missing":
            item.file != nil && item.path != nil
        default:
            false
        }
    }

    /// Kinds whose row IS a file jit wrote, and reads as one: its name,
    /// the folders that tell it from its siblings, and the fact about it.
    /// Deliberately narrow — a row naming someone else's config is about
    /// the config's contents, not the file.
    static let fileRowKinds: Set<String> = ["stale_pointers"]

    /// A file row in three parts. Nil for every other kind, which keeps
    /// its sentence.
    static func rowParts(_ item: DoctorItem) -> RowParts? {
        guard fileRowKinds.contains(item.kind), let file = filePath(item) else {
            return nil
        }
        let url = URL(fileURLWithPath: file)
        let name = url.lastPathComponent
        guard !name.isEmpty else {
            return nil
        }
        return RowParts(name: name, folder: rowFolder(url.deletingLastPathComponent().path), fact: rowFact(item, file: file))
    }

    /// The last two folders above the file. Four `.env.pointers` differ by
    /// the folder they sit in, and the whole path truncated in the middle
    /// hid exactly that part; the ⋯ menu still copies the full path.
    static func rowFolder(_ directory: String) -> String {
        let parts = homePath(directory).split(separator: "/").map(String.init)
        return parts.suffix(2).joined(separator: "/")
    }

    /// The finding's own sentence with the path it opens with taken off:
    /// the row already shows the file, and repeating it in full left no
    /// width for what the sentence actually said.
    static func rowFact(_ item: DoctorItem, file: String) -> String {
        var text = item.summary
        for prefix in [file, homePath(file)] where text.hasPrefix(prefix + " ") {
            text = String(text.dropFirst(prefix.count + 1))
        }
        return upperFirst(shortenVaultClause(text))
    }

    /// jit names the vault group twice in one sentence ("lists 2 secrets
    /// under x/, and the vault has nothing under x/"). The second naming
    /// is the half a reader skips, so it becomes a fact after a middle
    /// dot. A sentence that does not repeat itself is left exactly as jit
    /// wrote it, and so is one jit words differently later.
    static func shortenVaultClause(_ text: String) -> String {
        let clause = ", and the vault has nothing under "
        guard let range = text.range(of: clause) else {
            return text
        }
        let group = String(text[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        let before = String(text[..<range.lowerBound])
        guard !group.isEmpty, before.contains(group) else {
            return text
        }
        return before + " · the vault holds none"
    }

    static func upperFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    static func homePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
