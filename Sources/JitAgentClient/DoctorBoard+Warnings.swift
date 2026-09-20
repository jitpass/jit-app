// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

extension BoardContext {
    /// Recommended and Tidy up: the records one Attach fixes, the nested
    /// MCP wrappers one migrate collapses, the profiles no tool uses, the
    /// backup and the old format, then every other warning by kind.
    func warningCards(_ warnings: [DoctorItem]) -> [DoctorCard] {
        let records = warnings.filter { DoctorAdvice.recordKinds.contains($0.kind) }
        var cards = grouped(records, by: attachConfig).map(recordCard)
        cards += grouped(warnings.filter { $0.kind == "mcp_nested" }) { $0.path ?? "" }.map(nestedCard)
        let unused = warnings.filter { $0.kind == "no_known_tool" }
        if !unused.isEmpty {
            cards.append(noKnownToolCard(unused))
        }
        let loggedOut = warnings.filter { $0.kind == "not_logged_in" }
        if !loggedOut.isEmpty {
            cards.append(notLoggedInCard(loggedOut))
        }
        for kind in ["backup", "legacy_envelope"] {
            let items = warnings.filter { $0.kind == kind }
            if !items.isEmpty {
                cards.append(kind == "backup" ? backupCard(items) : legacyCard(items))
            }
        }
        let special = DoctorAdvice.recordKinds.union(["mcp_nested", "no_known_tool", "not_logged_in", "backup", "legacy_envelope"])
        return cards + genericCards(warnings.filter { !special.contains($0.kind) }, problem: false)
    }

    // MARK: - Records

    /// The config a record finding's Attach records, else the one that
    /// starts its tools.
    func attachConfig(_ item: DoctorItem) -> String {
        DoctorAdvice.attachTargets(item).first?.config ?? item.config ?? item.configs?.first ?? ""
    }

    /// Every profile one Attach covers, deleted record or none, in one
    /// card that names the files and lists the profiles on demand.
    func recordCard(_ rows: [DoctorItem]) -> DoctorCard {
        let config = attachConfig(rows[0])
        let count = rows.count
        let deleted = rows.filter { $0.kind == "config_deleted" }
        let one = count == 1
        let title = if deleted.count == count {
            one ? "1 profile records a deleted config" : "\(count) profiles record a deleted config"
        } else if deleted.isEmpty {
            one ? "1 profile records no config" : "\(count) profiles record no config"
        } else {
            "\(count) profiles don't record the config that starts them"
        }
        var card = DoctorCard(
            id: "record:\(config)", tier: DoctorBoard.tier(of: rows[0], problem: false), title: title, items: rows,
            subject: one ? (rows[0].profile ?? "1 profile") : "\(count) profiles"
        )
        let recorded = DoctorAdvice.recordedFiles(deleted.flatMap { $0.owners ?? [] })
        let files = recorded.first.map { short($0) + (recorded.count > 1 ? " and \(recorded.count - 1) more" : "") } ?? "a config"
        let gone = recorded.count > 1 ? "which are deleted" : "which is deleted"
        let starts = short(config) + (one ? " starts its tool" : " starts their tools")
        let calm = "Nothing is broken; no secret changes."
        card.reason = if deleted.count == count {
            "\(one ? "It records" : "They record") \(files), \(gone). \(starts) now. \(calm)"
        } else if deleted.isEmpty {
            "\(starts), but \(one ? "it records" : "they record") no config. \(calm)"
        } else {
            "\(deleted.count) record \(files), \(gone), and \(count - deleted.count) record none. \(starts) now. \(calm)"
        }
        card.listed = rows.map {
            DoctorListedRow(name: $0.profile ?? "?", note: $0.kind == "config_deleted" ? "records a deleted config" : "records no config")
        }
        card.file = config.nilIfEmpty
        let attach = DoctorAdvice.attachActions(rows, among: all).first { $0.planned == .attach(config: config) }
        if let attach {
            card.primary = DoctorButton(one ? "Attach…" : "Attach \(count)…", .run([attach]))
        }
        card.menu = configEntries(config) + [.button(terminalButton(attach.map { [$0] } ?? []))]
        return card
    }

    /// Show … in Finder, Copy Path and a separator, for a file. The label is
    /// a parameter because most of these paths ARE someone else's config,
    /// but not all: a stale pointer record is jit's own file, and calling it
    /// a config sends the reader looking for a tool that owns it.
    func configEntries(_ config: String, label: String = "Show Config in Finder") -> [DoctorMenuEntry] {
        guard !config.isEmpty else {
            return []
        }
        return [
            .button(DoctorButton(label, .reveal(config))), .button(DoctorButton("Copy Path", .copyPath(config))),
            .separator
        ]
    }

    /// What the Finder entry calls the card's file.
    func fileMenuLabel(_ item: DoctorItem) -> String {
        item.kind == "stale_pointers" ? "Show File in Finder" : "Show Config in Finder"
    }

    // MARK: - Nested MCP wrappers

    /// One card per config: the servers that start jit inside jit, and
    /// the migrate that collapses them. Attach first when the same config
    /// has an Attach card: the migrate reads the profiles' records.
    func nestedCard(_ rows: [DoctorItem]) -> DoctorCard {
        let config = rows[0].path ?? ""
        let one = rows.count == 1
        var card = DoctorCard(
            id: "mcp_nested:\(config)", tier: DoctorBoard.tier(of: rows[0], problem: false),
            title: one ? "1 MCP server starts jit inside jit" : "\(rows.count) MCP servers start jit inside jit", items: rows
        )
        card.reason = "Still working. Migrating \(short(config)) again collapses \(one ? "it" : "each") to one wrapper."
            + (attachConfigs.contains(config) ? " Attach first." : "")
        let servers = rows.compactMap { BoardText.quoted($0.detail) }
        card.detail = servers.isEmpty ? nil : servers.joined(separator: " · ")
        card.file = config.nilIfEmpty
        let actions = DoctorAdvice.actions(for: rows[0])
        let migrate = actions.first { !isUndo($0) }
        if let migrate {
            let inApp = migrate.planned != nil
            card.primary = DoctorButton(inApp ? "Migrate…" : "Migrate in Terminal", inApp ? .run([migrate]) : .terminal(migrate.command))
            card.primaryProminent = inApp
        }
        let others = actions.filter { $0 != migrate }
        card.menu = configEntries(config) + actionButtons(others).map(DoctorMenuEntry.button)
            + [.button(terminalButton(migrate.map { [$0] } ?? []))]
        return card
    }

    func isUndo(_ action: DoctorAction) -> Bool {
        if case .undoMigration = action.planned {
            return true
        }
        return action.command.hasPrefix("jit migrate undo")
    }

    // MARK: - Tidy rows

    func noKnownToolCard(_ rows: [DoctorItem]) -> DoctorCard {
        let title = rows.count == 1 ? "1 profile no tool uses" : "\(rows.count) profiles no tool uses"
        var card = DoctorCard(id: "no_known_tool", tier: DoctorBoard.tier(of: rows[0], problem: false), title: title, items: rows)
        card.reason = rows.compactMap(\.profile).joined(separator: ", ")
        card.primary = DoctorButton("Review…", .review)
        card.primaryProminent = false
        return card
    }

    func backupCard(_ rows: [DoctorItem]) -> DoctorCard {
        var card = DoctorCard(id: "backup", tier: DoctorBoard.tier(of: rows[0], problem: false), title: "No recovery file yet", items: rows)
        card.reason = "the vault only opens on this Mac"
        if let export = DoctorAdvice.actions(for: rows[0]).first {
            card.primary = DoctorButton("Save…", .run([export]))
        }
        card.primaryProminent = false
        return card
    }

    func legacyCard(_ rows: [DoctorItem]) -> DoctorCard {
        let count = rows[0].detail.flatMap { Int($0.prefix { $0.isNumber }) }
        let title = switch count {
        case nil: "Secrets in the older format"
        case 1: "1 secret in the older format"
        case let count?: "\(count) secrets in the older format"
        }
        var card = DoctorCard(id: "legacy_envelope", tier: DoctorBoard.tier(of: rows[0], problem: false), title: title, items: rows)
        card.reason = "can't tell if a value was swapped on disk"
        if let reencrypt = DoctorAdvice.actions(for: rows[0]).first {
            card.primary = DoctorButton("Re-encrypt…", .run([reencrypt]))
        }
        card.primaryProminent = false
        return card
    }

    // MARK: - Every other kind

    /// A card per kind for everything the board has no words of its own
    /// for: the kind's title, its note, and doctor's buttons as the window
    /// always offered them; one row per finding when there are several.
    /// A row's buttons: the finding's own actions, plus Edit where the row
    /// is ABOUT a file jit wrote and the reader's next move is to look at
    /// it. Deliberately not on every row with a file — most of those name
    /// someone else's config, where opening an editor is not the point —
    /// but a stale pointer record is jit's own text, and deciding whether
    /// to keep it means reading it.
    func rowButtons(_ item: DoctorItem) -> [DoctorButton] {
        var buttons = actionButtons(DoctorAdvice.actions(for: item))
        if let edit = editButton(item) {
            buttons.insert(edit, at: 0)
        }
        return buttons
    }

    /// Edit, for a row about a file jit wrote whose contents decide what to
    /// do with it. Shared by the row path and the single-finding card, which
    /// is the whole point: it used to exist only on rows, so a lone stale
    /// record — much the commonest case — offered no way to read the file
    /// and made Delete the card's one prominent button instead.
    func editButton(_ item: DoctorItem) -> DoctorButton? {
        guard item.kind == "stale_pointers", let file = DoctorAdvice.filePath(item) else {
            return nil
        }
        return DoctorButton("Edit", .edit(file))
    }

    func genericCards(_ items: [DoctorItem], problem: Bool) -> [DoctorCard] {
        DoctorAdvice.groups(items, among: all).map { group in
            let tier = DoctorBoard.tier(of: group.items[0], problem: problem)
            var card = DoctorCard(id: "kind:\(group.kind)", tier: tier, title: group.title, items: group.items)
            if DoctorAdvice.listedKinds.contains(group.kind) {
                return orphanCard(card)
            }
            var actions = group.groupActions
            if group.items.count == 1 {
                let item = group.items[0]
                let text = DoctorAdvice.rowText(item)
                let path = DoctorAdvice.rowIsPath(item)
                card.reason = tier == .tidy ? text : [group.note, path ? nil : text].compactMap { $0 }.joined(separator: " ")
                card.detail = tier != .tidy && path ? text : nil
                card.file = DoctorAdvice.filePath(item)
                actions += DoctorAdvice.actions(for: item)
            } else {
                card.reason = tier == .tidy ? "\(group.items.count) of them" : group.note
                card.rows = group.items.map { item in
                    DoctorCardRow(
                        id: item.id, text: DoctorAdvice.rowText(item), mono: DoctorAdvice.rowIsPath(item),
                        file: DoctorAdvice.filePath(item),
                        buttons: rowButtons(item)
                    )
                }
            }
            let primary = actions.first { !isUndo($0) }
            // Reading the record is the first move, and every other action
            // on it deletes it: a destructive button must never be the one
            // prominent call to action on a card that is asking the user to
            // decide.
            let edit = group.items.count == 1 ? editButton(group.items[0]) : nil
            if let edit {
                card.primary = edit
                card.primaryProminent = false
            } else if let primary {
                card.primary = actionButtons([primary]).first
                card.primaryProminent = tier != .tidy && primary.argv != nil
            }
            let file = card.file.map { configEntries($0, label: fileMenuLabel(group.items[0])) } ?? []
            let rest = actionButtons(edit == nil ? actions.filter { $0 != primary } : actions)
            card.menu = file + rest.map(DoctorMenuEntry.button)
            if tier != .tidy {
                card.menu.append(.button(terminalButton(primary.map { [$0] } ?? [])))
            }
            return card
        }
    }

    /// The orphaned secrets: a count and one way in. Reviewing them is
    /// reading, so the button is not prominent and nothing on this card
    /// deletes: the list is where a secret is looked at and chosen, and
    /// deleting without looking is what the old Delete All invited.
    func orphanCard(_ base: DoctorCard) -> DoctorCard {
        var card = base
        let count = card.items.count
        card.title = count == 1 ? "1 orphaned secret" : "\(count) orphaned secrets"
        card.reason = "in the vault, but no profile jit can see uses \(count == 1 ? "it" : "them")"
        card.primary = DoctorButton("Review…", .open(.orphans))
        card.primaryProminent = false
        card.menu = [.button(DoctorButton("Open in Terminal", .terminal("jit vault orphans")))]
        return card
    }
}
