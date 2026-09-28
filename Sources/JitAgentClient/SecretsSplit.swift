// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

// Only secrets go into the vault (design/secrets-only-vault.md in the jit
// repo). jit decides where each .env variable goes; the app shows it, lets
// the user move a line, and passes that choice back as a flag. No decision
// here beyond the user's own.

/// `jit migrate preview <files> --format json`: where each .env variable
/// would go, settings with their values and secrets never, and each MCP
/// config's .env files. Read-only: the vault is never opened.
public struct MigratePreview: Codable, Sendable, Equatable {
    public var files: [File]

    public struct File: Codable, Sendable, Equatable {
        public var path: String
        /// "env", "mcp", or "other".
        public var kind: String
        public var vars: [Var]?
        public var mcp: MCP?

        public init(path: String, kind: String, vars: [Var]? = nil, mcp: MCP? = nil) {
            self.path = path
            self.kind = kind
            self.vars = vars
            self.mcp = mcp
        }
    }

    public typealias Var = MigratePreviewVar

    public typealias MCP = MigratePreviewMCP

    public init(files: [File]) {
        self.files = files
    }

    public static func arguments(for paths: [String]) -> [String] {
        ["migrate", "preview"] + paths + ["--format", "json"]
    }

    public static func parse(_ data: Data) throws -> MigratePreview {
        try JSONDecoder().decode(MigratePreview.self, from: data)
    }
}

/// One .env variable in a preview.
public struct MigratePreviewVar: Codable, Sendable, Equatable {
    public var name: String
    /// "secret", "check" or "setting".
    public var varClass: String
    public var inVault: Bool
    /// Set for a setting only.
    public var value: String?

    enum CodingKeys: String, CodingKey {
        case name
        case varClass = "class"
        case inVault = "in_vault"
        case value
    }

    public init(name: String, varClass: String, inVault: Bool, value: String? = nil) {
        self.name = name
        self.varClass = varClass
        self.inVault = inVault
        self.value = value
    }
}

/// What an MCP config would move.
public struct MigratePreviewMCP: Codable, Sendable, Equatable {
    public var reads: [String]
    public var inlineServers: Int
    public var covered: Bool

    enum CodingKeys: String, CodingKey {
        case reads
        case inlineServers = "inline_servers"
        case covered
    }

    public init(reads: [String], inlineServers: Int, covered: Bool) {
        self.reads = reads
        self.inlineServers = inlineServers
        self.covered = covered
    }
}

/// The Protect sheet's state: the preview, and each line the user moved.
public struct ProtectSplit: Sendable, Equatable {
    public var preview: MigratePreview
    /// "path\u{0}NAME" → in the vault, for lines the user changed.
    public private(set) var choices: [String: Bool] = [:]

    public init(preview: MigratePreview) {
        self.preview = preview
    }

    private static func key(_ file: String, _ name: String) -> String {
        file + "\u{0}" + name
    }

    /// Where a line goes now: the user's choice, else jit's.
    public func inVault(file: String, variable: MigratePreview.Var) -> Bool {
        choices[Self.key(file, variable.name)] ?? variable.inVault
    }

    public mutating func set(file: String, variable: MigratePreview.Var, inVault: Bool) {
        let choiceKey = Self.key(file, variable.name)
        if inVault == variable.inVault {
            choices[choiceKey] = nil
        } else {
            choices[choiceKey] = inVault
        }
    }

    public var envFiles: [MigratePreview.File] {
        preview.files.filter { $0.kind == "env" }
    }

    /// The flags that carry the user's changes: FILE:NAME, so a choice on
    /// one file's line never reaches a same-named variable in another.
    public var flags: [String] {
        var out: [String] = []
        for file in envFiles {
            for variable in file.vars ?? [] {
                guard let chosen = choices[Self.key(file.path, variable.name)] else {
                    continue
                }
                out += [chosen ? "--secret" : "--setting", file.path + ":" + variable.name]
            }
        }
        return out
    }

    public struct Counts: Equatable, Sendable {
        public var vault = 0
        public var check = 0
        public var settings = 0
    }

    /// One file's split: to the vault, of which to check, and settings.
    public func counts(_ file: MigratePreview.File) -> Counts {
        var counts = Counts()
        for variable in file.vars ?? [] {
            if inVault(file: file.path, variable: variable) {
                counts.vault += 1
                if variable.varClass == "check", choices[Self.key(file.path, variable.name)] == nil {
                    counts.check += 1
                }
            } else {
                counts.settings += 1
            }
        }
        return counts
    }

    public var totals: Counts {
        envFiles.reduce(into: Counts()) { total, file in
            let each = counts(file)
            total.vault += each.vault
            total.check += each.check
            total.settings += each.settings
        }
    }
}

public extension ScanWording {
    /// "Protect 2 files?" / "Protect ~/code/billing-sync/.env?", or
    /// "Protect 3 findings?" when wraps ride along.
    static func protectSheetTitle(_ split: ProtectSplit, home: String, wraps: [String] = []) -> String {
        let files = split.preview.files
        switch (files.count, wraps.count) {
        case (1, 0): return "Protect " + ScanNotices.abbreviate(files[0].path, home: home) + "?"
        case (0, 1): return "Protect the \(wraps[0]) command?"
        case (_, 0): return "Protect \(files.count) files?"
        default: return "Protect \(files.count + wraps.count) findings?"
        }
    }

    /// "2 secrets go to the vault. 10 settings stay as they are, in plain
    /// text." The file-keeps-working sentence follows it on the sheet.
    static func protectSheetSentence(_ split: ProtectSplit) -> String {
        let totals = split.totals
        var parts: [String] = []
        if totals.vault > 0 {
            parts.append((totals.vault == 1 ? "1 secret goes" : "\(totals.vault) secrets go") + " to the vault.")
        }
        if totals.settings > 0 {
            parts.append(totals.settings == 1
                ? "1 setting stays as it is, in plain text."
                : "\(totals.settings) settings stay as they are, in plain text.")
        }
        return parts.joined(separator: " ")
    }

    /// A card's line: "1 secret · 1 to check · 7 settings".
    static func protectCardNote(_ counts: ProtectSplit.Counts) -> String {
        var parts: [String] = []
        let secrets = counts.vault - counts.check
        if secrets > 0 {
            parts.append(secrets == 1 ? "1 secret" : "\(secrets) secrets")
        }
        if counts.check > 0 {
            parts.append("\(counts.check) to check")
        }
        if counts.settings > 0 {
            parts.append(counts.settings == 1 ? "1 setting" : "\(counts.settings) settings")
        }
        return parts.isEmpty ? "Nothing to move" : parts.joined(separator: " · ")
    }

    /// An MCP config whose .env this run protects: "Covered by
    /// billing-sync/.env above. It reads its secret from that file, so
    /// nothing else moves."
    static func protectCoveredNote(_ mcp: MigratePreview.MCP, home: String) -> String {
        let named = mcp.reads.map { shortEnvName($0, home: home) }
        return "Covered by " + named.joined(separator: ", ") + " above. It reads its secret from "
            + (named.count == 1 ? "that file" : "those files") + ", so nothing else moves."
    }

    /// "billing-sync/.env": the folder and the file, enough to tell two
    /// .env files apart on one sheet.
    static func shortEnvName(_ path: String, home _: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent
    }
}

/// `jit vault settings --format json`: the plain settings beside the vault.
public struct VaultSettingsListing: Codable, Sendable, Equatable {
    public var settings: [Setting]

    public typealias Setting = VaultSetting

    public init(settings: [Setting]) {
        self.settings = settings
    }

    public static let arguments = ["vault", "settings", "--format", "json"]

    public static func parse(_ data: Data) throws -> VaultSettingsListing {
        try JSONDecoder().decode(VaultSettingsListing.self, from: data)
    }
}

/// One plain setting: its path, value, and who names it.
public struct VaultSetting: Codable, Sendable, Equatable, Identifiable {
    public var path: String
    public var value: String
    public var usedBy: [String]

    enum CodingKeys: String, CodingKey {
        case path, value
        case usedBy = "used_by"
    }

    public init(path: String, value: String, usedBy: [String] = []) {
        self.path = path
        self.value = value
        self.usedBy = usedBy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        value = try container.decode(String.self, forKey: .value)
        usedBy = try container.decodeIfPresent([String].self, forKey: .usedBy) ?? []
    }

    public var id: String {
        path
    }

    public var group: String {
        path.split(separator: "/", maxSplits: 1).first.map(String.init) ?? path
    }

    public var name: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

/// `jit vault move-out|move-in <paths> --yes --format json`.
public struct SettingMoveResult: Codable, Sendable, Equatable {
    public var moved: [Moved]

    public struct Moved: Codable, Sendable, Equatable {
        public var path: String
        public var scan: String?
        public var profiles: [String]
    }

    public static func arguments(out: Bool, paths: [String]) -> [String] {
        ["vault", out ? "move-out" : "move-in"] + paths + ["--yes", "--format", "json"]
    }

    public static func parse(_ output: String) throws -> SettingMoveResult {
        try JSONDecoder().decode(SettingMoveResult.self, from: Data(output.utf8))
    }
}

/// `jit migrate settings --yes --format json`: the cleanup for profiles
/// protected before settings stayed plain.
public struct MigrateSettingsResult: Codable, Sendable, Equatable {
    public var read: Int
    public var moved: [String]
    public var checks: [String]
    public var skipped: [Skip]

    public struct Skip: Codable, Sendable, Equatable {
        public var path: String
        public var reason: String
    }

    public static let arguments = ["migrate", "settings", "--yes", "--format", "json"]
    /// The same read, moving nothing: which entries would move.
    public static let dryRunArguments = ["migrate", "settings", "--dry-run", "--yes", "--format", "json"]

    /// The dry run's verdict as the sheet lists it. `moves` is jit's own
    /// list, whole: its candidates are every entry protected from a .env,
    /// which can include ones the app already saw checked, and the sheet
    /// must list every path the button then moves. `stays` is what else it
    /// is known to have looked at: its checks and the app's unchecked
    /// entries it did not move. Both counts are the lengths of what is
    /// listed, so neither can go negative.
    public func verdict(unchecked: [String]) -> (moves: [String], stays: [String]) {
        let moves = Array(Set(moved)).sorted()
        let stays = Set(checks + unchecked).subtracting(moves).sorted()
        return (moves, stays)
    }

    /// Vault paths as the sheet lists them: each profile (the first path
    /// segment) with its variable names, both sorted.
    public static func byProfile(_ paths: [String]) -> [(String, [String])] {
        Dictionary(grouping: paths) { String($0.split(separator: "/").first ?? Substring($0)) }
            .map { ($0.key, $0.value.map { String($0.split(separator: "/").last ?? Substring($0)) }.sorted()) }
            .sorted { $0.0 < $1.0 }
    }

    public static func parse(_ output: String) throws -> MigrateSettingsResult {
        try JSONDecoder().decode(MigrateSettingsResult.self, from: Data(output.utf8))
    }
}

public extension VaultListing {
    /// Entries protected from a .env before jit kept settings out of the
    /// vault: the scan's class was never recorded, so some may be
    /// settings. What the Vault window's cleanup banner counts: it cannot
    /// know how many ARE settings without reading them.
    var uncheckedFromEnv: [VaultSecret] {
        // A 1Password link is never read by the cleanup (a plain copy would
        // cut the link), so it never gets a class: counting it would keep
        // the banner up for good.
        secrets.filter { $0.secretClass == "dotenv" && $0.scan == nil && !$0.isLinked }
    }
}

public extension VaultListing {
    /// The Vault window's profiles: every group the vault lists, plus any
    /// profile whose values are all plain settings now, which the vault
    /// listing alone would drop from the sidebar.
    func groups(matching filter: String, settings: VaultSettingsListing?) -> [VaultGroup] {
        var out = groups(matching: filter)
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let known = Set(out.map(\.name))
        var extra: [String] = []
        for setting in settings?.settings ?? [] where !known.contains(setting.group) && !extra.contains(setting.group) {
            if needle.isEmpty || setting.group.lowercased().contains(needle) || setting.name.lowercased().contains(needle) {
                extra.append(setting.group)
            }
        }
        out += extra.map { VaultGroup(name: $0, secrets: []) }
        return out.sorted { $0.name < $1.name }
    }
}

public extension VaultSettingsListing {
    /// One profile's settings, in name order.
    func settings(in group: String) -> [Setting] {
        settings.filter { $0.group == group }.sorted { $0.name < $1.name }
    }
}
