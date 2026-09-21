// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One line of `jit scan --format ndjson`. Only the fields the report window
/// shows are decoded; `value_preview` is deliberately not among them, so a
/// secret fragment can never reach the app's memory or screen.
public struct ScanFinding: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var findingType: String
    public var severity: String
    public var filePath: String
    /// The line the secret sits on, 1-based, when the scanner knows it. A
    /// file-level finding (a whole .env, a credentials file) has none.
    public var line: Int?
    public var evidence: String
    public var remedy: String
    public var fixCommand: String?
    public var archived: Bool
    /// The file is test scaffolding (a *_test.go, a testdata/ path) or the
    /// value is a documented example. Reported, left out of the score
    /// (audit.CountedAsSecret), and set apart so they never read as a breach.
    public var testFixture: Bool
    public var sourceExample: Bool
    /// For a finding in an AI agent's cache or store: the agent's name
    /// ("Claude Code") and what that part of its cache holds ("edit
    /// history"), the scanner's own words (schema 0.21.0).
    public var agent: String?
    public var cacheArea: String?
    /// The file the credential actually lives in, for a cached copy.
    public var originPath: String?
    /// The variable or key the finding is about ("ANTHROPIC_API_KEY",
    /// "github.com/oauth_token"), when the scanner knows it.
    public var keyName: String?

    enum CodingKeys: String, CodingKey {
        case id = "record_id"
        case findingType = "finding_type"
        case severity
        case filePath = "file_path"
        case line
        case evidence
        case remedy
        case fixCommand = "fix_command"
        case archived
        case testFixture = "test_fixture"
        case sourceExample = "source_example"
        case agent
        case cacheArea = "cache_area"
        case originPath = "origin_path"
        case keyName = "key_name"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        findingType = try container.decode(String.self, forKey: .findingType)
        severity = try container.decode(String.self, forKey: .severity)
        filePath = try container.decode(String.self, forKey: .filePath)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        evidence = try container.decode(String.self, forKey: .evidence)
        remedy = try container.decode(String.self, forKey: .remedy)
        fixCommand = try container.decodeIfPresent(String.self, forKey: .fixCommand)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        testFixture = try container.decodeIfPresent(Bool.self, forKey: .testFixture) ?? false
        sourceExample = try container.decodeIfPresent(Bool.self, forKey: .sourceExample) ?? false
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        cacheArea = try container.decodeIfPresent(String.self, forKey: .cacheArea)
        originPath = try container.decodeIfPresent(String.self, forKey: .originPath)
        keyName = try container.decodeIfPresent(String.self, forKey: .keyName)
    }

    /// A verbatim copy of a confirmed credential in an AI agent's cache.
    public var isAgentCopy: Bool {
        findingType == "agent_cached_secret"
    }

    /// A deep scan's find: an exact copy of a secret already in the vault
    /// (schema 0.23.0). `keyName` is the vault path.
    public var isVaultCopy: Bool {
        findingType == "vault_copy"
    }

    /// A token the scan recognised by its format inside an AI agent's
    /// cache (schema 0.22.0): what `jit migrate redact` rewrites.
    public var isCacheShape: Bool {
        findingType == "exposed_secret" && agent != nil
    }

    /// True when `jit migrate` can fix it; false means only the user can.
    public var migratable: Bool {
        remedy == "migrate"
    }

    /// The tool a `jit wrap <tool>` fix names, if that is the fix.
    public var wrapTool: String? {
        guard let fix = fixCommand, fix.hasPrefix("jit wrap ") else {
            return nil
        }
        let tool = fix.dropFirst("jit wrap ".count).trimmingCharacters(in: .whitespaces)
        return tool.isEmpty ? nil : tool
    }

    /// Test scaffolding or a documented example: real-looking, counted by
    /// the scanner, but almost never a live credential.
    public var scaffolding: Bool {
        testFixture || sourceExample
    }
}

public struct ScanSummary: Codable, Sendable, Equatable {
    public var totalFindings: Int
    public var riskLevel: String
    public var exposureScore: Int
    public var secretsTotal: Int
    public var secretsProtected: Int
    public var secretsMigratable: Int
    public var filesScanned: Int
    public var scanTime: String?
    /// Set on a deep scan (schema 0.23.0): the vault's secrets were
    /// searched for, and `vaultSecretsChecked` says how many.
    public var deep: Bool?
    public var vaultSecretsChecked: Int?

    enum CodingKeys: String, CodingKey {
        case totalFindings = "total_findings"
        case riskLevel = "risk_level"
        case exposureScore = "exposure_score"
        case secretsTotal = "secrets_total"
        case secretsProtected = "secrets_protected"
        case secretsMigratable = "secrets_migratable"
        case filesScanned = "files_scanned"
        case scanTime = "scan_time"
        case deep
        case vaultSecretsChecked = "vault_secrets_checked"
    }
}

/// A whole scan: the findings in the order the CLI emitted them, and the
/// summary record that closes the stream.
public struct ScanReport: Sendable, Equatable {
    public var findings: [ScanFinding]
    public var summary: ScanSummary

    public init(findings: [ScanFinding], summary: ScanSummary) {
        self.findings = findings
        self.summary = summary
    }

    public var migratable: [ScanFinding] {
        findings.filter { $0.migratable && !$0.scaffolding }
    }

    /// Findings only the user can fix, less the agent-cache copies and the
    /// vault copies, which each have their own section.
    public var manual: [ScanFinding] {
        findings.filter { !$0.migratable && !$0.scaffolding && !$0.isAgentCopy && !$0.isVaultCopy && !$0.isCacheShape }
    }

    /// Tokens found by format in agent caches, and the same by file: the
    /// agent-caches card's second half, with Redact as its verb.
    public var cacheShapes: [ScanFinding] {
        findings.filter { $0.isCacheShape && !$0.scaffolding }
    }

    public var cacheShapeGroups: [ScanFileGroup] {
        ScanFileGroup.group(cacheShapes)
    }

    /// Exact copies of vaulted secrets a deep scan found in the open.
    public var vaultCopies: [ScanFinding] {
        findings.filter(\.isVaultCopy)
    }

    public var agentCopies: [ScanFinding] {
        findings.filter(\.isAgentCopy)
    }

    /// The cached copies grouped by agent and cache area, in first-seen
    /// order: "Claude Code · edit history · 9 copies" is what a reader can
    /// act on, where nine hash-named file rows are not.
    public var agentCacheGroups: [ScanAgentGroup] {
        ScanAgentGroup.group(agentCopies)
    }

    /// Credentials in MCP server configs (.mcp.json, mcp.json, Claude
    /// Desktop's and Claude Code's), grouped by file. `key_name` is
    /// "server/KEY"; remedy "migrate" for an env block or --env-file,
    /// "manual" for args, headers and url, which no process can be handed.
    public var mcpByFile: [ScanFileGroup] {
        ScanFileGroup.group(findings.filter { $0.findingType == "mcp_embedded_secret" && !$0.scaffolding })
    }

    /// How many cached copies sit in one agent's caches, by the scanner's
    /// label for it.
    public func agentCopies(in agent: String) -> Int {
        agentCopies.filter { $0.agent == agent }.count
    }

    public var scaffolding: [ScanFinding] {
        findings.filter(\.scaffolding)
    }

    /// The manual findings grouped by file, in first-seen order, so a file
    /// with three exposed lines is one row with three lines under it rather
    /// than the same path printed three times.
    public var manualByFile: [ScanFileGroup] {
        ScanFileGroup.group(manual)
    }

    /// The terminal commands that protect everything in `migratable`, in
    /// one go: every `jit migrate <path>` folded into a single migrate call
    /// (one plan, one confirmation, one Touch ID), then any other fix (a
    /// `jit wrap <tool>`) once each, in the order the scan listed them.
    /// Empty when nothing is migratable.
    public var protectAllCommands: [String] {
        let migratePrefix = "jit migrate "
        var targets: [String] = []
        var others: [String] = []
        for f in migratable {
            guard let fix = f.fixCommand else {
                continue
            }
            if fix.hasPrefix(migratePrefix) {
                let target = String(fix.dropFirst(migratePrefix.count))
                if !targets.contains(target) {
                    targets.append(target)
                }
            } else if !others.contains(fix) {
                others.append(fix)
            }
        }
        var commands: [String] = []
        if !targets.isEmpty {
            commands.append(migratePrefix + targets.joined(separator: " "))
        }
        return commands + others
    }

    /// What the app's Protect All runs: every migratable file once, in a
    /// single `jit migrate a b c --yes` (one plan, one Touch ID), then each
    /// `jit wrap <tool>` once. Paths are the findings' own, absolute, so
    /// nothing is parsed back out of a shell-quoted command.
    public var protectPlan: ProtectPlan {
        var plan = ProtectPlan()
        for f in migratable {
            if let tool = f.wrapTool {
                if !plan.wrap.contains(tool) {
                    plan.wrap.append(tool)
                }
            } else if f.fixCommand?.hasPrefix("jit migrate ") == true, !plan.migrate.contains(f.filePath) {
                plan.migrate.append(f.filePath)
            }
        }
        return plan
    }

    /// Parses the ndjson stream. Lines that are neither a finding nor the
    /// summary are skipped, so a new record type never breaks the app; a
    /// stream with no summary is an error, since it means the scan did not
    /// finish.
    public static func parse(_ data: Data) throws -> ScanReport {
        let decoder = JSONDecoder()
        var findings: [ScanFinding] = []
        var summary: ScanSummary?
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            guard let typed = try? decoder.decode(ScanRecordType.self, from: line) else {
                continue
            }
            switch typed.recordType {
            case "finding":
                if let f = try? decoder.decode(ScanFinding.self, from: line) {
                    findings.append(f)
                }
            case "scan_summary":
                summary = try decoder.decode(ScanSummary.self, from: line)
            default:
                continue
            }
        }
        guard let summary else {
            throw ScanReportError.noSummary
        }
        return ScanReport(findings: findings, summary: summary)
    }
}

/// Just enough of any record to dispatch on its type.
private struct ScanRecordType: Decodable {
    var recordType: String

    enum CodingKeys: String, CodingKey {
        case recordType = "record_type"
    }
}

public enum ScanReportError: Error, Equatable {
    case noSummary
}

/// One file's findings, for the report's per-file rows.
public struct ScanFileGroup: Sendable, Equatable, Identifiable {
    public var filePath: String
    public var findings: [ScanFinding]

    public var id: String {
        filePath
    }

    /// The worst severity in the group, so the row's dot is the one a
    /// reader must not miss.
    public var severity: String {
        findings.map(\.severity).max { Self.rank($0) < Self.rank($1) } ?? "low"
    }

    static func rank(_ severity: String) -> Int {
        switch severity {
        case "critical": 4
        case "high": 3
        case "medium": 2
        case "low": 1
        default: 0
        }
    }

    public static func group(_ findings: [ScanFinding]) -> [ScanFileGroup] {
        var order: [String] = []
        var byFile: [String: [ScanFinding]] = [:]
        for f in findings {
            if byFile[f.filePath] == nil {
                order.append(f.filePath)
            }
            byFile[f.filePath, default: []].append(f)
        }
        return order.map { ScanFileGroup(filePath: $0, findings: byFile[$0] ?? []) }
    }
}

/// One agent's cache area and the copies found in it.
public struct ScanAgentGroup: Sendable, Equatable, Identifiable {
    public var agent: String
    public var area: String
    public var findings: [ScanFinding]

    public var id: String {
        agent + "·" + area
    }

    public var severity: String {
        findings.map(\.severity).max { ScanFileGroup.rank($0) < ScanFileGroup.rank($1) } ?? "low"
    }

    /// The files the copies came from, deduplicated, first-seen order.
    public var origins: [String] {
        var seen: Set<String> = []
        return findings.compactMap(\.originPath).filter { seen.insert($0).inserted }
    }

    public var files: [String] {
        var seen: Set<String> = []
        return findings.map(\.filePath).filter { seen.insert($0).inserted }
    }

    public static func group(_ findings: [ScanFinding]) -> [ScanAgentGroup] {
        var order: [String] = []
        var byKey: [String: ScanAgentGroup] = [:]
        for f in findings {
            let agent = f.agent ?? "an AI agent"
            let area = f.cacheArea ?? "cache"
            let key = agent + "·" + area
            if byKey[key] == nil {
                order.append(key)
                byKey[key] = ScanAgentGroup(agent: agent, area: area, findings: [])
            }
            byKey[key]?.findings.append(f)
        }
        return order.compactMap { byKey[$0] }
    }
}
