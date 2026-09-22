// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The menu bar panel's row values, under one rule (windows.md, "Panel
/// rows"): a number plus one or two words, never more than about
/// fourteen characters, and the dot beside it is the window's own mark —
/// or nothing, when the value is a plain count and no state is claimed.
/// A green dot says why in words, never with a number; a red or amber
/// value is the worst fact, and the window's header names it. The panel
/// counts; the window names.
public enum PanelValue {
    /// The dot beside a value: the window's mark, or none.
    public enum Tone: Equatable, Sendable {
        case none, green, amber, red
    }

    public struct Row: Equatable, Sendable {
        public var text: String
        public var tone: Tone

        public init(_ text: String, _ tone: Tone = .none) {
            self.text = text
            self.tone = tone
        }
    }

    /// "25 secrets": a count, no state.
    public static func vault(secrets: Int) -> Row {
        Row(count(secrets, "secret"))
    }

    /// The worst fact across the agents' cards.
    public static func agents(copies: Int, needing: Int, scanned: Bool) -> Row {
        if copies > 0 {
            return Row(count(copies, "copy", "copies"), .red)
        }
        if needing > 0 {
            return Row(needsYou(needing), .amber)
        }
        return scanned ? Row("all set", .green) : Row("not searched", .amber)
    }

    /// Broken first, then a session that ran out, then a key in a file
    /// (Findings' fact, amber here), then the count of what runs through jit.
    public static func tools(broken: Int, expired: Int, toProtect: Int, wrapped: Int) -> Row {
        if broken > 0 {
            return Row("\(broken) broken", .red)
        }
        if expired > 0 {
            return Row("\(expired) expired", .amber)
        }
        if toProtect > 0 {
            return Row("\(toProtect) to protect", .amber)
        }
        // A count of what works is good news, and still a count: no dot.
        return wrapped == 0 ? Row("none wrapped") : Row("\(wrapped) wrapped")
    }

    /// The lock state lives in the panel's head; the row only says whether
    /// the service is there.
    public static func service(running: Bool) -> Row {
        Row(running ? "running" : "not running")
    }

    public static func grants(active: Int) -> Row {
        active == 0 ? Row("none") : Row("\(active) active")
    }

    /// A file naming a secret the vault lacks outranks today's reads.
    public static func decoys(files: Int, broken: Int, readsToday: Int) -> Row? {
        guard files > 0 else {
            return nil
        }
        if broken > 0 {
            return Row("\(broken) broken", .red)
        }
        if readsToday > 0 {
            return Row(count(readsToday, "read") + " today", .amber)
        }
        return Row(count(files, "file"))
    }

    public static func doctor(problems: Int, warnings: Int, checked: Bool, checking: Bool) -> Row {
        guard checked else {
            return Row(checking ? "checking…" : "not checked")
        }
        if problems > 0 {
            return Row(count(problems, "problem"), .red)
        }
        if warnings > 0 {
            return Row(count(warnings, "warning"), .amber)
        }
        return Row("healthy", .green)
    }

    /// The header's to-do lines, counted; the window names them.
    public static func findings(todos: Int, worst: Tone, scanned: Bool, scanning: Bool) -> Row {
        guard scanned else {
            return Row(scanning ? "scanning…" : "not scanned")
        }
        if todos == 0 {
            return Row("all clear", .green)
        }
        return Row("\(todos) to do", worst == .none ? .amber : worst)
    }

    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) " + (n == 1 ? singular : plural ?? singular + "s")
    }

    static func needsYou(_ n: Int) -> String {
        n == 1 ? "1 needs you" : "\(n) need you"
    }
}
