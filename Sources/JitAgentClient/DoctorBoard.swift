// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The Doctor window as cards grouped by impact rather than by kind: what
/// is broken now, what is recommended, what is only tidying. A card covers
/// every finding one fix covers (a profile's missing secrets, the profiles
/// one Attach records a config on), says what stops working in the user's
/// words, and carries one primary button and a ⋯ menu for the rest.
///
/// The tier comes from the engine's own split: every problem is Broken
/// now, whatever its kind, and a warning is Recommended or Tidy up by kind.
/// The kind only groups. The buttons are `DoctorAdvice.actions(for:)`'s,
/// never new ones: the board changes where a button sits, not what it runs
/// or how it confirms.
public struct DoctorBoard: Equatable, Sendable {
    public enum Tier: String, CaseIterable, Sendable, Identifiable {
        case broken, recommended, tidy

        public var id: String {
            rawValue
        }

        public var title: String {
            switch self {
            case .broken: "Broken now"
            case .recommended: "Recommended"
            case .tidy: "Tidy up"
            }
        }
    }

    /// The header mark's colour, as the menu bar mark uses them.
    public enum Mark: Equatable, Sendable {
        case red, amber, green
    }

    public var headline: String
    public var subline: String?
    public var mark: Mark
    public var cards: [DoctorCard]
    /// What the user ignored, folded under the cards; counted nowhere.
    public var ignored: [DoctorIgnoredRow] = []

    public func cards(in tier: Tier) -> [DoctorCard] {
        cards.filter { $0.tier == tier }
    }

    public var isEmpty: Bool {
        cards.isEmpty
    }

    /// Warnings worth doing something about soon; every other warning is
    /// Tidy up, and so is a kind this app doesn't know yet.
    public static let recommendedKinds: Set<String> = [
        "config_deleted", "config_not_recorded", "mcp_nested", "jit_path_upgrade", "mount_stale", "mount", "duplicates",
        "service", "install", "completion", "not_logged_in"
    ]

    /// The tier of a finding: a problem is always Broken now.
    public static func tier(of item: DoctorItem, problem: Bool) -> Tier {
        if problem {
            return .broken
        }
        return recommendedKinds.contains(item.kind) ? .recommended : .tidy
    }
}

/// One card: a title that says what stops working, a reason, an optional
/// monospaced line naming the file and profile, and its buttons. A card
/// of several independent fixes (pointer files) has rows, each with its
/// own button; a card over a list the reader may want (the profiles one
/// Attach covers) has it behind a disclosure.
public struct DoctorCard: Equatable, Sendable, Identifiable {
    /// Stable across a recheck that finds the same things.
    public var id: String
    public var tier: DoctorBoard.Tier
    public var title: String
    public var reason: String?
    public var detail: String?
    public var rows: [DoctorCardRow] = []
    public var listed: [DoctorListedRow] = []
    /// What the disclosure calls the listed rows ("profiles").
    public var listNoun = "profiles"
    public var primary: DoctorButton?
    /// The primary is the card's blue button; false when it only shows
    /// something (Show in Finder) or hands off to the terminal.
    public var primaryProminent = true
    public var menu: [DoctorMenuEntry] = []
    /// The findings the card covers.
    public var items: [DoctorItem]
    /// The file the card is about, for right-click Show in Finder.
    public var file: String?
    /// The tools that won't start until this card is fixed.
    public var tools: [String] = []
    /// Its tools are MCP servers, which pick a new value up on restart.
    public var restartsInEditor = false
    /// What the done and failed lines call it.
    public var subject: String

    public init(id: String, tier: DoctorBoard.Tier, title: String, items: [DoctorItem], subject: String? = nil) {
        self.id = id
        self.tier = tier
        self.title = title
        self.items = items
        self.subject = subject ?? title
    }

    /// "Show the 7 profiles" / "Hide the 7 profiles".
    public func disclosure(open: Bool) -> String {
        let noun = listed.count == 1 ? String(listNoun.dropLast()) : listNoun
        return (open ? "Hide the " : "Show the ") + (listed.count == 1 ? noun : "\(listed.count) \(noun)")
    }
}

/// A row of a multi-row card: one finding, its line, its own buttons.
public struct DoctorCardRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var mono: Bool
    public var file: String?
    public var buttons: [DoctorButton]
}

/// A disclosure row: a name and what is true of it.
public struct DoctorListedRow: Equatable, Sendable, Identifiable {
    public var name: String
    public var note: String

    public var id: String {
        name
    }
}

/// A card's button: runs doctor's actions (one after the other, each with
/// its own dialog), or does something local and harmless: select a file in
/// Finder, copy its path, open the terminal, list what a row covers.
public struct DoctorButton: Equatable, Sendable, Identifiable {
    public enum Command: Equatable, Sendable {
        case run([DoctorAction])
        case reveal(String)
        /// Open the file in the editor chosen in Settings.
        case edit(String)
        case copyPath(String)
        case terminal(String)
        case review
        /// `jit doctor ignore …` per finding, then a recheck.
        case ignore([[String]])
        /// `jit doctor unignore …`.
        case unignore([String])
    }

    public var title: String
    public var command: Command

    public init(_ title: String, _ command: Command) {
        self.title = title
        self.command = command
    }

    public var id: String {
        title + "|" + help
    }

    public var steps: [DoctorAction] {
        if case let .run(steps) = command {
            return steps
        }
        return []
    }

    /// jit asks for Touch ID while it runs.
    public var presence: Bool {
        steps.contains(where: \.presence)
    }

    public var destructive: Bool {
        steps.contains(where: \.destructive)
    }

    /// What a hover shows: the command, or the file.
    public var help: String {
        switch command {
        case let .run(steps): steps.map(\.command).joined(separator: "\n")
        case let .reveal(path), let .edit(path), let .copyPath(path): path
        case let .terminal(command): command
        case .review: ""
        case let .ignore(commands): commands.map { "jit " + $0.joined(separator: " ") }.joined(separator: "\n")
        case let .unignore(command): "jit " + command.joined(separator: " ")
        }
    }
}

public enum DoctorMenuEntry: Equatable, Sendable {
    case button(DoctorButton)
    case separator
}

public extension DoctorBoard {
    /// The board for a report. `home` shortens paths to ~.
    static func make(_ report: DoctorReport, home: String = NSHomeDirectory()) -> DoctorBoard {
        let all = report.problems + report.warnings
        let context = BoardContext(all: all, home: home)
        let order = Tier.allCases
        let cards = (context.problemCards(report.problems) + context.warningCards(report.warnings)).enumerated()
            .sorted { (order.firstIndex(of: $0.element.tier) ?? 0, $0.offset) < (order.firstIndex(of: $1.element.tier) ?? 0, $1.offset) }
            .map(\.element)
            .map { card in
                var card = card
                if let ignore = card.ignoreButton {
                    card.menu += (card.menu.isEmpty ? [] : [.separator]) + [.button(ignore)]
                }
                return card
            }
        let (headline, subline) = heading(cards)
        let mark: Mark = cards.contains { $0.tier == .broken } ? .red
            : cards.contains { $0.tier == .recommended } ? .amber : .green
        return DoctorBoard(headline: headline, subline: subline, mark: mark, cards: cards, ignored: ignoredRows(report.ignored))
    }

    /// "2 tools won't start" and the tools, then what else fails; else the
    /// problems to fix; else nothing broken and what is left to tidy.
    static func heading(_ cards: [DoctorCard]) -> (String, String?) {
        let broken = cards.filter { $0.tier == .broken }
        var tools: [String] = []
        for tool in broken.flatMap(\.tools) where !tools.contains(tool) {
            tools.append(tool)
        }
        let rest = cards.count - broken.count
        let tidy = rest == 1 ? "1 thing to tidy" : "\(rest) things to tidy"
        if !tools.isEmpty {
            let also = broken.filter { $0.tools.isEmpty && $0.items.first?.kind == "profile_missing" }
                .map { lowerFirst($0.title) + " too" }
            let subline = ([BoardText.list(tools)] + also).joined(separator: " · ")
            return (tools.count == 1 ? "1 tool won't start" : "\(tools.count) tools won't start", subline)
        }
        if !broken.isEmpty {
            var titles = broken.prefix(2).map(\.title)
            if broken.count > 2 {
                titles.append("\(broken.count - 2) more")
            }
            return (broken.count == 1 ? "1 problem to fix" : "\(broken.count) problems to fix", titles.joined(separator: " · "))
        }
        if cards.contains(where: { $0.tier == .recommended }) {
            return ("Nothing is broken", tidy)
        }
        return ("Nothing needs you", rest == 0 ? nil : tidy)
    }

    private static func lowerFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }
}

/// Wording shared by the card builders.
enum BoardText {
    /// "a", "a and b", "a, b and c".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }

    /// `path` with the home folder as ~.
    static func short(_ path: String, _ home: String) -> String {
        VaultRmPlan.short(path, home)
    }

    static func dialogTitle(_ action: DoctorAction) -> String {
        action.buttonTitle
    }

    /// The first `"name"` in a sentence: the server an mcp finding names.
    static func quoted(_ text: String?) -> String? {
        guard let text, let open = text.firstIndex(of: "\"") else {
            return nil
        }
        let rest = text[text.index(after: open)...]
        guard let close = rest.firstIndex(of: "\"") else {
            return nil
        }
        let name = String(rest[..<close])
        return name.isEmpty ? nil : name
    }
}

public extension DoctorAction {
    /// The title with "…" when the button opens a dialog before it runs.
    var buttonTitle: String {
        let asks = destructive || input != nil || needs != .nothing || planned != nil
        return asks && !title.hasSuffix("…") ? title + "…" : title
    }
}
