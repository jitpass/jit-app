// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// `jit doctor ignore` and `unignore` (jit 2.1), as a finding carries them:
/// the kind and name jit keys it by, and the argv that runs it. The app
/// runs only an argv that is exactly `jit doctor ignore|unignore …`: the
/// report is data, and data never picks the command.
public struct DoctorIgnoreCommand: Codable, Sendable, Equatable {
    public var kind: String?
    public var name: String?
    public var argv: [String]

    public init(kind: String? = nil, name: String? = nil, argv: [String]) {
        self.kind = kind
        self.name = name
        self.argv = argv
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        kind = try box.decodeIfPresent(String.self, forKey: .kind)
        name = try box.decodeIfPresent(String.self, forKey: .name)
        argv = try box.decodeIfPresent([String].self, forKey: .argv) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case kind, name, argv
    }

    /// What the app runs, without "jit" and with --format json; nil unless
    /// the argv is `jit doctor <verb>` and something after it.
    public func arguments(_ verb: String) -> [String]? {
        guard argv.count > 3, argv[0] == "jit", argv[1] == "doctor", argv[2] == verb else {
            return nil
        }
        return Array(argv.dropFirst()) + ["--format", "json"]
    }
}

/// What `jit doctor ignore|unignore … --format json` answers.
public struct DoctorIgnoreResult: Decodable, Sendable, Equatable {
    public struct Entry: Decodable, Sendable, Equatable {
        public var kind: String
        public var name: String
    }

    public var ignored: [Entry]
    public var unignored: [Entry]
    public var error: String?

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        ignored = try box.decodeIfPresent([Entry].self, forKey: .ignored) ?? []
        unignored = try box.decodeIfPresent([Entry].self, forKey: .unignored) ?? []
        let error = try box.decodeIfPresent(String.self, forKey: .error)
        self.error = error?.isEmpty == true ? nil : error
    }

    enum CodingKeys: String, CodingKey {
        case ignored, unignored, error
    }

    public static func parse(_ data: Data) throws -> DoctorIgnoreResult {
        try JSONDecoder().decode(DoctorIgnoreResult.self, from: data)
    }
}

/// One line of the folded "N ignored" list: what it is, where it would
/// be, since when, and Show Again.
public struct DoctorIgnoredRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var section: DoctorBoard.Tier
    public var since: String?
    public var showAgain: DoctorButton?

    /// "mcp-okta-mcp-server · Broken now · since 2026-09-19".
    public var text: String {
        ([name, section.title] + (since.map { ["since \($0)"] } ?? [])).joined(separator: " · ")
    }
}

public extension DoctorBoard {
    /// Where an ignored finding would be: jit says whether it is a problem
    /// or a warning, and a warning's kind picks its tier as on the board.
    static func section(ofIgnored item: DoctorItem) -> Tier {
        tier(of: item, problem: item.severity == "problem")
    }

    /// The ignored findings, one row per kind and name.
    static func ignoredRows(_ items: [DoctorItem]) -> [DoctorIgnoredRow] {
        var rows: [DoctorIgnoredRow] = []
        for item in items {
            let kind = item.unignore?.kind ?? item.ignore?.kind ?? item.kind
            let name = item.unignore?.name ?? item.ignore?.name ?? item.profile ?? item.path ?? item.summary
            let id = "ignored:\(kind)|\(name)"
            guard !rows.contains(where: { $0.id == id }) else {
                continue
            }
            let again = item.unignore?.arguments("unignore").map { DoctorButton("Show Again", .unignore($0)) }
            rows.append(DoctorIgnoredRow(
                id: id, name: name, section: section(ofIgnored: item), since: item.ignoredSince, showAgain: again
            ))
        }
        return rows
    }
}

public extension DoctorCard {
    /// Ignore on the ⋯ menu: every finding the card covers, when each has
    /// a command jit wrote for it.
    var ignoreButton: DoctorButton? {
        let commands = items.compactMap { $0.ignore?.arguments("ignore") }
        guard !items.isEmpty, commands.count == items.count else {
            return nil
        }
        var unique: [[String]] = []
        for command in commands where !unique.contains(command) {
            unique.append(command)
        }
        return DoctorButton("Ignore", .ignore(unique))
    }

    /// The one line a problem card's Ignore asks first; nil for advice,
    /// which is ignored without a question.
    var ignoreConfirmation: String? {
        guard tier == .broken else {
            return nil
        }
        if !tools.isEmpty {
            let what = BoardText.list(tools) + (tools.count == 1 ? " still fails" : " still fail")
            return what + "; Doctor just stops counting " + (tools.count == 1 ? "it." : "them.")
        }
        let endings = [(" won't start", " still won't start"), (" fails", " still fails"), (" fail", " still fail")]
        guard let (suffix, still) = endings.first(where: { title.hasSuffix($0.0) }) else {
            return "It still fails; Doctor just stops counting it."
        }
        let them = suffix == " fail" ? "them." : "it."
        return String(title.dropLast(suffix.count)) + still + "; Doctor just stops counting " + them
    }

    /// Whether a finding this card covers was ignored and came back
    /// because it changed.
    var changedSinceIgnored: Bool {
        items.contains { $0.ignoreChanged == true }
    }
}

extension BoardContext {
    /// Profiles whose login ran out (not_logged_in, jit 2.1): one card, a
    /// row per profile, each logging in in the terminal, since the login
    /// is interactive.
    func notLoggedInCard(_ rows: [DoctorItem]) -> DoctorCard {
        let title = rows.count == 1 ? "1 profile isn't logged in" : "\(rows.count) profiles aren't logged in"
        var card = DoctorCard(id: "not_logged_in", tier: DoctorBoard.tier(of: rows[0], problem: false), title: title, items: rows)
        card.reason = (rows.count == 1 ? "Its tool fails" : "Their tools fail") + " until you log in again. Logging in opens the terminal."
        card.rows = rows.map { item in
            let login = (item.fixes ?? []).filter(\.external).map { DoctorButton("Log In in Terminal", .terminal($0.command)) }
            let others = actionButtons(DoctorAdvice.actions(for: item).filter { action in
                !(item.fixes ?? []).contains { $0.external && $0.command == action.command }
            })
            return DoctorCardRow(id: item.id, text: loginRowText(item), mono: true, file: item.file, buttons: login + others)
        }
        return card
    }

    /// "aws --profile dev · ~/.aws/config [profile dev]": what fails, and
    /// where it is set; the profile and its file for any other tool.
    func loginRowText(_ item: DoctorItem) -> String {
        guard let launcher = item.launchers?.first else {
            return item.summary
        }
        let place = short(launcher.file) + (launcher.detail.map { " " + $0 } ?? "")
        if launcher.kind == "aws", let detail = launcher.detail {
            return "aws --profile " + Self.awsName(detail) + " · " + place
        }
        return (item.profile ?? launcher.kind) + " · " + place
    }
}
