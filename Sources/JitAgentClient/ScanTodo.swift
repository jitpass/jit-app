// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One line of the Findings header: a tier that has something in it, said
/// in its card's own numbers and ending in its card's own verb. The rule
/// the header follows is that every number it prints is a number on a
/// card below it — the old "10 of 26 secrets protected" counted
/// deduplicated secrets that no card listed, and read as sixteen things to
/// protect when none of them was one (docs/design/mockups/Findings-header).
public struct ScanTodo: Equatable, Sendable, Identifiable {
    public enum Action: Equatable, Sendable {
        /// Show that tier's card.
        case show(ScanTier)
        /// Offer the depth question: this scan did not look for vault copies.
        case deepScan
        /// Nothing to do; the line is the good news.
        case none
    }

    public var text: String
    /// The verb, as a link at the end of the line; nil when the line asks
    /// nothing.
    public var verb: String?
    public var action: Action

    /// The line as one sentence: text, the app's separator, the verb. The
    /// view sets the verb as a link, so the sentence wraps as a sentence.
    public var sentence: String {
        verb.map { text + " · " + $0 } ?? text
    }

    public var id: String {
        text
    }
}

public extension ScanReport {
    /// The header's lines, in the cards' order. `deepAvailable` is whether
    /// the vault holds a secret, so a regular scan can be told what it did
    /// not look for.
    func todos(deepAvailable: Bool) -> [ScanTodo] {
        var lines = [vaultCopyTodo, protectTodo, needsYouTodo, cachedCopiesTodo, cacheShapeTodo].compactMap { $0 }
        if lines.isEmpty {
            lines.append(ScanTodo(text: "Nothing in the open.", verb: nil, action: .none))
        }
        if summary.deep != true, vaultCopies.isEmpty, deepAvailable {
            lines.append(ScanTodo(
                text: "Copies of your vaulted secrets are not looked for by a regular scan",
                verb: "run a deep scan", action: .deepScan
            ))
        }
        return lines
    }

    /// "4 still have plaintext copies in 32 files": distinct vault entries,
    /// and the card's file count.
    private var vaultCopyTodo: ScanTodo? {
        let copies = vaultCopies
        guard !copies.isEmpty else {
            return nil
        }
        let secrets = max(1, Set(copies.compactMap(\.keyName)).count)
        let files = Set(copies.map(\.filePath)).count
        let text = secrets == 1
            ? "1 still has a plaintext copy in " + Self.files(files)
            : "\(secrets) still have plaintext copies in " + Self.files(files)
        return ScanTodo(text: text + "", verb: "clear the copies", action: .show(.vaultCopies))
    }

    private var protectTodo: ScanTodo? {
        let n = groups(in: .protect).count
        guard n > 0 else {
            return nil
        }
        let text = Self
            .files(n) + (n == 1 ? " holds a secret jit can move into the vault" : " hold secrets jit can move into the vault")
        return ScanTodo(text: text, verb: n == 1 ? "protect it" : "protect them", action: .show(.protect))
    }

    private var needsYouTodo: ScanTodo? {
        let n = groups(in: .needsYou).count
        guard n > 0 else {
            return nil
        }
        let text = Self.files(n) + (n == 1 ? " holds a secret only you can fix" : " hold secrets only you can fix")
        return ScanTodo(text: text, verb: n == 1 ? "rotate or move it" : "rotate or move them", action: .show(.needsYou))
    }

    /// Copies of vaulted secrets an agent kept: the Clean Caches half of
    /// the agent-caches card.
    private var cachedCopiesTodo: ScanTodo? {
        let copies = agentCopies
        guard !copies.isEmpty else {
            return nil
        }
        let groups = agentCacheGroups
        let place = groups.count == 1 ? "\(groups[0].agent)'s \(groups[0].area)" : "\(groups.count) agent caches"
        let text = (copies.count == 1 ? "1 copy of a vaulted secret sits in " : "\(copies.count) copies of vaulted secrets sit in ") +
            place + ""
        return ScanTodo(text: text, verb: "clean the caches", action: .show(.agentCaches))
    }

    /// Tokens found by format in agent files: the Redact half.
    private var cacheShapeTodo: ScanTodo? {
        let groups = cacheShapeGroups
        guard !groups.isEmpty else {
            return nil
        }
        let lines = groups.reduce(0) { $0 + $1.findings.count }
        let places = Set(groups.flatMap { $0.findings.compactMap(\.foundIn) })
        let place = places.count == 1
            ? Self.files(groups.count) + " of " + places.first!
            : "\(groups.count) AI agent file" + (groups.count == 1 ? "" : "s")
        let text = (lines == 1 ? "1 flagged line sits in " : "\(lines) flagged lines sit in ") + place + ""
        return ScanTodo(text: text, verb: lines == 1 ? "redact it" : "redact them", action: .show(.agentCaches))
    }

    private static func files(_ n: Int) -> String {
        "\(n) file" + (n == 1 ? "" : "s")
    }
}
