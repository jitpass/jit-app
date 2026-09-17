// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One env var an env-wrap fills, from `jit wrap list --format json`.
public struct ToolInject: Codable, Sendable, Equatable {
    public var name: String
    public var vaultPath: String?
    public var stored: Bool

    enum CodingKeys: String, CodingKey {
        case name = "var"
        case vaultPath = "vault_path"
        case stored
    }

    public init(name: String, vaultPath: String? = nil, stored: Bool = false) {
        self.name = name
        self.vaultPath = vaultPath
        self.stored = stored
    }
}

/// One tool jit knows: wrapped (from `~/.jit/wrap.json`) or in the catalog.
/// Every state word here is jit's own verdict; the app adds no check of its
/// own. `kind` is "shim", "grant", "capture", "rungrant" or "native".
public struct ToolRecord: Codable, Sendable, Equatable, Identifiable {
    public var tool: String
    public var kind: String
    public var catalog: Bool
    public var doc: String?
    public var installedPath: String?
    public var wrapped: Bool
    public var addedUnix: Int64?
    /// "ok", "missing" or "broken" for a wrapped tool; nil otherwise.
    public var shim: String?
    public var shimDetail: String?
    public var profile: String?
    public var injects: [ToolInject]
    public var with: String?
    public var capture: String?
    public var verifyHint: String?
    public var sources: [String]
    public var tokenCommand: String?
    public var nativeCategory: String?
    public var vaultSecrets: Int
    /// With `--discover`: whether `jit wrap <tool>` would find a key, and
    /// where (a "~"-rooted file, or the tool's own export command). nil
    /// when the listing did not look.
    public var keyFound: Bool?
    public var keySource: String?

    enum CodingKeys: String, CodingKey {
        case tool, kind, catalog, doc, wrapped, shim, profile, injects, with, capture, sources
        case keyFound = "key_found"
        case keySource = "key_source"
        case installedPath = "installed_path"
        case addedUnix = "added_unix"
        case shimDetail = "shim_detail"
        case verifyHint = "verify_hint"
        case tokenCommand = "token_command"
        case nativeCategory = "native_category"
        case vaultSecrets = "vault_secrets"
    }

    public init(
        tool: String,
        kind: String,
        catalog: Bool = true,
        doc: String? = nil,
        installedPath: String? = nil,
        wrapped: Bool = false,
        shim: String? = nil,
        shimDetail: String? = nil,
        injects: [ToolInject] = [],
        capture: String? = nil,
        verifyHint: String? = nil,
        nativeCategory: String? = nil,
        vaultSecrets: Int = 0
    ) {
        self.tool = tool
        self.kind = kind
        self.catalog = catalog
        self.doc = doc
        self.installedPath = installedPath
        self.wrapped = wrapped
        self.shim = shim
        self.shimDetail = shimDetail
        self.injects = injects
        self.capture = capture
        self.verifyHint = verifyHint
        self.nativeCategory = nativeCategory
        self.vaultSecrets = vaultSecrets
        sources = []
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        tool = try box.decode(String.self, forKey: .tool)
        kind = try box.decode(String.self, forKey: .kind)
        catalog = try box.decodeIfPresent(Bool.self, forKey: .catalog) ?? false
        doc = try box.decodeIfPresent(String.self, forKey: .doc)
        installedPath = try box.decodeIfPresent(String.self, forKey: .installedPath)
        wrapped = try box.decodeIfPresent(Bool.self, forKey: .wrapped) ?? false
        addedUnix = try box.decodeIfPresent(Int64.self, forKey: .addedUnix)
        shim = try box.decodeIfPresent(String.self, forKey: .shim)
        shimDetail = try box.decodeIfPresent(String.self, forKey: .shimDetail)
        profile = try box.decodeIfPresent(String.self, forKey: .profile)
        injects = try box.decodeIfPresent([ToolInject].self, forKey: .injects) ?? []
        with = try box.decodeIfPresent(String.self, forKey: .with)
        capture = try box.decodeIfPresent(String.self, forKey: .capture)
        verifyHint = try box.decodeIfPresent(String.self, forKey: .verifyHint)
        sources = try box.decodeIfPresent([String].self, forKey: .sources) ?? []
        tokenCommand = try box.decodeIfPresent(String.self, forKey: .tokenCommand)
        nativeCategory = try box.decodeIfPresent(String.self, forKey: .nativeCategory)
        vaultSecrets = try box.decodeIfPresent(Int.self, forKey: .vaultSecrets) ?? 0
        keyFound = try box.decodeIfPresent(Bool.self, forKey: .keyFound)
        keySource = try box.decodeIfPresent(String.self, forKey: .keySource)
    }

    public var id: String {
        tool
    }

    /// The AI CLIs in the catalog, the ten the website's "ai agents" page
    /// lists. The one list the app keeps about tools by name (design §10).
    public static let agentTools: Set<String> = [
        "claude", "codex", "gemini", "cursor-agent", "copilot", "cline", "opencode", "kiro-cli", "openai", "hf"
    ]

    /// The name the scanner uses for each agent's cache, so a row can find
    /// its own cached copies. openai and hf are API CLIs with no cache.
    public static let agentLabels: [String: String] = [
        "claude": "Claude Code",
        "gemini": "Gemini CLI",
        "codex": "Codex CLI",
        "cursor-agent": "Cursor",
        "copilot": "GitHub Copilot CLI",
        "cline": "Cline",
        "opencode": "OpenCode",
        "kiro-cli": "Kiro"
    ]

    public var isAgent: Bool {
        Self.agentTools.contains(tool)
    }

    /// The scanner's name for this agent's cache, when it is an agent.
    public var agentLabel: String? {
        Self.agentLabels[tool]
    }

    /// The catalog line up to its first comma or semicolon: what the
    /// credential is, without the mechanism the CLI's evidence line adds
    /// ("AWS access keys", not "AWS access keys, served via
    /// credential_process, which SDKs consult too").
    public var shortDoc: String {
        guard let doc else {
            return ""
        }
        let cut = doc.firstIndex { $0 == "," || $0 == ";" } ?? doc.endIndex
        return String(doc[..<cut])
    }

    public var isNative: Bool {
        kind == "native"
    }

    /// A grant wrap: the tool reads a credential file a migrate category
    /// serves as a global mount (`with`), and the shim takes the grant.
    public var isGrant: Bool {
        kind == "grant"
    }

    /// Whether the mount's file has been migrated: the category stamps
    /// its mount name as the vault class.
    public var mountMigrated: Bool {
        isGrant && vaultSecrets > 0
    }

    /// Installed here, or wrapped (a wrapped tool is listed even when its
    /// real binary is off this PATH, because its shim still is).
    public var isInstalled: Bool {
        installedPath != nil || wrapped
    }

    /// The shim exists and points at an executable, with the profile in
    /// place for an env-wrap.
    public var isHealthy: Bool {
        wrapped && shim == "ok"
    }

    /// A native tool counts as protected once its migration has stored
    /// secrets of its class.
    public var isProtected: Bool {
        isNative ? vaultSecrets > 0 : isHealthy
    }

    /// The row's state word, in the design's vocabulary (§3).
    public var stateLabel: String {
        if isNative {
            return isProtected ? "protected" : "not protected"
        }
        switch (wrapped, shim) {
        case (false, _): return "not wrapped"
        case (true, "ok"): return kind == "capture" ? "catching" : "wrapped"
        case (true, "missing"): return "shim missing"
        default: return "shim broken"
        }
    }

    /// Whether every var the wrap injects has a secret behind it.
    public var allStored: Bool {
        injects.allSatisfy(\.stored)
    }

    /// Whether there is anything for jit to protect for this tool, from
    /// the listing's discovery and the last whole-Mac scan. The question
    /// the row has to answer before "wrap or not" means anything.
    public func keyState(scan: ScanReport?) -> ToolKeyState {
        if isProtected {
            return .protected
        }
        if let source = keySource, keyFound == true {
            return .found(source)
        }
        if let f = scan?.findings.first(where: { $0.fixCommand == "jit wrap " + tool && !$0.scaffolding }) {
            return .found(f.filePath)
        }
        if let f = scan?.findings.first(where: { finding in
            guard let key = finding.keyName?.uppercased(), !finding.scaffolding, !finding.archived else {
                return false
            }
            return injects.contains { $0.name.uppercased() == key }
        }) {
            return .found(f.filePath)
        }
        if isNative, let category = nativeCategory, let f = scan?.findings.first(where: {
            $0.findingType == "credential_file" && !$0.scaffolding && Self.nativeFile($0.filePath, matches: category)
        }) {
            return .found(f.filePath)
        }
        // A grant tool's key is the mount's file; found means "migrate it".
        if isGrant, !mountMigrated, let mount = with, let f = scan?.findings.first(where: {
            !$0.scaffolding && Self.mountFile($0, matches: mount)
        }) {
            return .found(f.filePath)
        }
        if keyFound == false || scan != nil {
            return .none
        }
        return .unknown
    }

    /// Which global mount a finding's file feeds, by finding type or place.
    static func mountFile(_ f: ScanFinding, matches mount: String) -> Bool {
        switch mount {
        case "sops": f.findingType == "sops_age_key" || f.filePath.contains("/sops/age/")
        case "gcp": f.filePath.contains("/gcloud/")
        case "npm": f.filePath.hasSuffix("/.npmrc")
        case "netrc": f.filePath.hasSuffix("/.netrc")
        case "pypi": f.filePath.hasSuffix("/.pypirc")
        default: false
        }
    }

    /// Which native category a credential file belongs to, by the file's
    /// place: the scanner reports the file, migrate names the category.
    static func nativeFile(_ path: String, matches category: String) -> Bool {
        switch category {
        case "aws": path.contains("/.aws/")
        case "docker": path.contains("/.docker/")
        case "git": path.hasSuffix("/.git-credentials") || path.hasSuffix("/.gitconfig")
        case "terraform": path.contains("/.terraform.d/") || path.hasSuffix("/.terraformrc")
        default: false
        }
    }
}

/// The answer to "is there a key to protect": already handled, found
/// somewhere on this Mac, looked and found nothing, or not looked yet.
public enum ToolKeyState: Sendable, Equatable {
    case protected
    case found(String)
    case none
    case unknown

    /// A key was found somewhere jit can take it from.
    public var found: Bool {
        if case .found = self {
            return true
        }
        return false
    }

    /// A key sits in a plaintext file, which is the state worth a colour:
    /// a token in a tool's own keychain login is encrypted at rest, and
    /// wrapping it is an improvement, not a fix.
    public var needsAction: Bool {
        if case let .found(source) = self {
            return source.hasPrefix("~") || source.hasPrefix("/")
        }
        return false
    }
}

/// `jit wrap list --all --format json`: the wrapped tools and the catalog,
/// with where each is installed.
public struct ToolListing: Codable, Sendable, Equatable {
    public var shimDir: String?
    public var shimDirOnPath: Bool
    public var rcFile: String?
    public var rcHasPathLine: Bool
    public var tools: [ToolRecord]

    enum CodingKeys: String, CodingKey {
        case tools
        case shimDir = "shim_dir"
        case shimDirOnPath = "shim_dir_on_path"
        case rcFile = "rc_file"
        case rcHasPathLine = "rc_has_path_line"
    }

    public init(tools: [ToolRecord], shimDirOnPath: Bool = true, rcHasPathLine: Bool = true) {
        self.tools = tools
        self.shimDirOnPath = shimDirOnPath
        self.rcHasPathLine = rcHasPathLine
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        shimDir = try box.decodeIfPresent(String.self, forKey: .shimDir)
        shimDirOnPath = try box.decodeIfPresent(Bool.self, forKey: .shimDirOnPath) ?? false
        rcFile = try box.decodeIfPresent(String.self, forKey: .rcFile)
        rcHasPathLine = try box.decodeIfPresent(Bool.self, forKey: .rcHasPathLine) ?? false
        tools = try box.decodeIfPresent([ToolRecord].self, forKey: .tools) ?? []
    }

    /// What is on this Mac: installed catalog tools and every wrapped one.
    public var installed: [ToolRecord] {
        tools.filter(\.isInstalled)
    }

    public var agents: [ToolRecord] {
        installed.filter(\.isAgent)
    }

    public var others: [ToolRecord] {
        installed.filter { !$0.isAgent }
    }

    public var wrapped: [ToolRecord] {
        tools.filter(\.wrapped)
    }

    /// Installed, wrappable, and not yet wrapped: shim, capture and run-grant
    /// kinds. Native tools are counted by their own protection, not here.
    public var toWrap: [ToolRecord] {
        installed.filter { !$0.wrapped && !$0.isNative }
    }

    public var broken: [ToolRecord] {
        wrapped.filter { !$0.isHealthy }
    }

    public func tool(named name: String) -> ToolRecord? {
        tools.first { $0.tool == name }
    }
}
