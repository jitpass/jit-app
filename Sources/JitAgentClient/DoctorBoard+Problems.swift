// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A tool that uses a profile, as the report itself names it: an MCP
/// server (from a record finding's tools or an mcp finding's sentence) or
/// a wrapped CLI.
struct BoardTool: Equatable {
    var name: String
    var config: String?
    var mcp: Bool
}

/// What the card builders share: the whole report, for what one finding
/// says about another (which tool uses a profile, which config has an
/// Attach card), and the home folder paths are shortened against.
struct BoardContext {
    let all: [DoctorItem]
    let home: String
    /// Profile name to the tools that use it, first seen first.
    let tools: [String: [BoardTool]]
    /// The configs an Attach card records.
    let attachConfigs: Set<String>

    init(all: [DoctorItem], home: String) {
        self.all = all
        self.home = home
        tools = Self.toolIndex(all)
        attachConfigs = Set(all.filter { DoctorAdvice.recordKinds.contains($0.kind) }
            .flatMap { DoctorAdvice.attachTargets($0).map(\.config) })
    }

    /// Every tool the report ties to a profile: the MCP servers and
    /// wrapped tools a finding's launchers name, and the server an mcp
    /// finding's sentence quotes ("okta-mcp-server" in ~/p/.mcp.json).
    static func toolIndex(_ all: [DoctorItem]) -> [String: [BoardTool]] {
        var index: [String: [BoardTool]] = [:]
        func add(_ profile: String?, _ tool: BoardTool) {
            guard let profile, !(index[profile] ?? []).contains(where: { $0.name == tool.name }) else {
                return
            }
            index[profile, default: []].append(tool)
        }
        for item in all {
            for launcher in item.launchers ?? [] {
                guard let name = launcher.detail else {
                    continue
                }
                if launcher.kind == "mcp" {
                    add(launcher.profile ?? item.profile, BoardTool(name: name, config: launcher.file.nilIfEmpty, mcp: true))
                } else if launcher.kind == "wrap" {
                    add(launcher.profile ?? item.profile, BoardTool(name: name, config: nil, mcp: false))
                }
            }
            if ["mcp", "mcp_nested", "jit_path_upgrade"].contains(item.kind), let name = BoardText.quoted(item.detail) {
                add(item.profile, BoardTool(name: name, config: item.path?.nilIfEmpty, mcp: true))
            }
        }
        return index
    }

    func short(_ path: String) -> String {
        BoardText.short(path, home)
    }

    /// Broken now, in the order a reader fixes them: the tools that won't
    /// start, then the configs naming missing profiles, the pointer files,
    /// and every other problem by kind.
    func problemCards(_ problems: [DoctorItem]) -> [DoctorCard] {
        let special: Set = ["missing", "corrupt", "profile_missing", "pointer_missing"]
        let secrets = problems.filter { $0.kind == "missing" || $0.kind == "corrupt" }
        var cards = grouped(secrets, by: secretKey).map(secretCard)
        cards += grouped(problems.filter { $0.kind == "profile_missing" }, by: missingProfileKey).map(missingProfileCard)
        let pointers = problems.filter { $0.kind == "pointer_missing" }
        if !pointers.isEmpty {
            cards.append(pointerCard(pointers, tier: .broken))
        }
        return cards + genericCards(problems.filter { !special.contains($0.kind) }, problem: true)
    }

    /// Items in first-seen order of their key, each key's items together.
    func grouped(_ items: [DoctorItem], by key: (DoctorItem) -> String) -> [[DoctorItem]] {
        var order: [String] = []
        var groups: [String: [DoctorItem]] = [:]
        for item in items {
            let name = key(item)
            if groups[name] == nil {
                order.append(name)
            }
            groups[name, default: []].append(item)
        }
        return order.compactMap { groups[$0] }
    }

    // MARK: - A profile's missing or unreadable secrets

    func secretKey(_ item: DoctorItem) -> String {
        "\(item.kind):\(item.profile ?? item.path ?? "")"
    }

    func missingProfileKey(_ item: DoctorItem) -> String {
        "\(missingFile(item))|\(item.launchers?.first?.kind ?? "")"
    }

    /// One card per profile: the tool that won't start, the secrets it
    /// lacks, and Set Value once per secret.
    func secretCard(_ rows: [DoctorItem]) -> DoctorCard {
        let first = rows[0]
        let corrupt = first.kind == "corrupt"
        let profile = first.profile ?? "?"
        let found = tools[profile] ?? []
        let names = found.map(\.name)
        let config = found.compactMap(\.config).first
        let title = names.isEmpty ? "Profile \(profile) can't start its tool" : "\(BoardText.list(names)) won't start"
        var card = DoctorCard(
            id: "\(first.kind):\(profile)", tier: .broken, title: title, items: rows,
            subject: names.isEmpty ? "Profile \(profile)" : BoardText.list(names)
        )
        let secrets = rows.map { $0.variable ?? $0.path ?? "?" }
        let what = corrupt ? "the vault can't read" : "the vault doesn't hold"
        card.reason = "Its profile names " + (secrets.count == 1 ? "a secret \(what): " : "\(secrets.count) secrets \(what): ")
            + secrets.joined(separator: ", ")
        card.detail = (config.map { short($0) + " · " } ?? "") + "profile \(profile)"
        card.tools = names
        card.restartsInEditor = found.contains(where: \.mcp)
        let manifest = (first.scope ?? "global") == "global" ? ProfileFiles.manifest(profile, home: home) : nil
        card.file = config ?? manifest
        let perRow = rows.map(DoctorAdvice.actions(for:))
        let steps = perRow.compactMap { actions in actions.first { $0.input != nil } }
        if !steps.isEmpty {
            let verb = corrupt ? "Replace Value" : "Set Value"
            card.primary = DoctorButton(steps.count == 1 ? verb + "…" : verb + "s…", .run(steps))
        }
        var menu: [DoctorMenuEntry] = []
        if let config {
            menu.append(.button(DoctorButton("Show Config in Finder", .reveal(config))))
        }
        if let manifest {
            menu.append(.button(DoctorButton("Show Profile File", .reveal(manifest))))
        }
        if let file = card.file {
            menu.append(.button(DoctorButton("Copy Path", .copyPath(file))))
        }
        let others = actionButtons(perRow.flatMap { $0 }.filter { !steps.contains($0) })
        card.menu = menu + [.separator] + others.map(DoctorMenuEntry.button) + [.button(terminalButton(steps))]
        return card
    }

    /// Buttons for actions, one per command; two of the same title name
    /// what each is for ("Show History · p/X").
    func actionButtons(_ actions: [DoctorAction]) -> [DoctorButton] {
        var unique: [DoctorAction] = []
        for action in actions where !unique.contains(where: { $0.command == action.command }) {
            unique.append(action)
        }
        return unique.map { action in
            let title = BoardText.dialogTitle(action)
            let clash = unique.filter { $0.title == action.title }.count > 1
            let target = action.argv?.first?.last { !$0.hasPrefix("-") } ?? action.command
            return DoctorButton(clash ? "\(title) · \(target)" : title, .run([action]))
        }
    }

    /// Open in Terminal: the card's commands as jit runs them there, with
    /// its own prompts; `jit doctor` when none is complete as written.
    func terminalButton(_ steps: [DoctorAction]) -> DoctorButton {
        let lines = steps.map(\.command).filter { !$0.isEmpty && DoctorItem.placeholder(in: $0) == nil }
        return DoctorButton("Open in Terminal", .terminal(lines.isEmpty ? "jit doctor" : lines.joined(separator: "\n")))
    }

    // MARK: - Configs naming a profile jit doesn't have

    func missingFile(_ item: DoctorItem) -> String {
        item.file ?? item.launchers?.first?.file ?? ""
    }

    /// One card per file and tool kind: what fails, in the command the user
    /// types ("aws --profile dev and admin fail"), and jit's advice once.
    func missingProfileCard(_ rows: [DoctorItem]) -> DoctorCard {
        let first = rows[0]
        let file = missingFile(first)
        let kind = first.launchers?.first?.kind ?? ""
        let details = rows.compactMap { $0.launchers?.first?.detail }
        let profiles = rows.compactMap(\.profile)
        let (title, isTool) = missingProfileTitle(kind: kind, details: details, file: file, count: rows.count)
        var card = DoctorCard(id: "profile_missing:\(file)|\(kind)", tier: .broken, title: title, items: rows)
        let has = switch profiles.count {
        case 1: "no such profile"
        case 2: "neither"
        default: "none of them"
        }
        let advice = DoctorAdvice.missingProfileAdvice(rows).map { " " + $0 + ($0.hasSuffix(".") ? "" : ".") } ?? ""
        card.reason = "\(short(file)) names \(BoardText.list(profiles)), and jit has \(has)." + advice
        if isTool {
            card.tools = details
            card.restartsInEditor = kind == "mcp"
        }
        if !file.isEmpty {
            card.file = file
            card.primary = DoctorButton("Show in Finder", .reveal(file))
            card.primaryProminent = false
            card.menu = [.button(DoctorButton("Copy Path", .copyPath(file))), .separator, .button(terminalButton([]))]
        }
        return card
    }

    /// The title, and whether its names are tools that won't start.
    func missingProfileTitle(kind: String, details: [String], file: String, count: Int) -> (String, Bool) {
        let fail = count == 1 ? "fails" : "fail"
        switch kind {
        case "aws":
            let names = details.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) }
                .map { $0.hasPrefix("profile ") ? String($0.dropFirst("profile ".count)) : $0 }
            return ("aws --profile \(BoardText.list(names)) \(fail)", false)
        case "mcp":
            return ("\(BoardText.list(details)) won't start", true)
        case "kube":
            let users = details.map { $0.hasPrefix("user ") ? String($0.dropFirst("user ".count)) : $0 }
            return ("kubectl fails as \(users.count == 1 ? "user" : "users") \(BoardText.list(users))", false)
        case "wrap":
            return ("\(BoardText.list(details)) \(fail)", true)
        case "shell_rc":
            return (count == 1 ? "A line in \(short(file)) fails" : "\(count) lines in \(short(file)) fail", false)
        default:
            return ("\(short(file)) names \(count == 1 ? "a profile" : "\(count) profiles") jit doesn't have", false)
        }
    }

    // MARK: - Pointer files

    /// One card for every pointer file naming a missing secret, a row each.
    func pointerCard(_ items: [DoctorItem], tier: DoctorBoard.Tier) -> DoctorCard {
        var files: [String] = []
        for file in items.compactMap(\.file) where !files.contains(file) {
            files.append(file)
        }
        let title = files.count <= 1
            ? "1 file points at \(items.count == 1 ? "a secret" : "secrets") the vault doesn't have"
            : "\(files.count) files point at secrets the vault doesn't have"
        var card = DoctorCard(id: "pointer_missing", tier: tier, title: title, items: items, subject: "Pointer file")
        card.rows = items.map { item in
            let text = item.file.flatMap { file in item.path.map { "\(short(file)) · \($0)" } } ?? item.summary
            return DoctorCardRow(
                id: item.id, text: text, mono: true, file: item.file,
                buttons: actionButtons(DoctorAdvice.actions(for: item))
            )
        }
        card.file = files.count == 1 ? files[0] : nil
        return card
    }
}
