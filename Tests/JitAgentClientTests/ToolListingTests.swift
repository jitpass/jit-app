// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class ToolListingTests: XCTestCase {
    /// A trimmed `jit wrap list --all --format json` from a real Mac.
    private let sample = """
    {
      "shim_dir": "/Users/me/.jit/shims", "shim_dir_on_path": true,
      "rc_file": "/Users/me/.zshrc", "rc_has_path_line": true,
      "tools": [
        {"tool": "clisso", "kind": "capture", "catalog": true, "doc": "temporary AWS credentials",
         "installed_path": "/opt/homebrew/bin/clisso", "wrapped": true, "added_unix": 1787031216,
         "shim": "ok", "capture": "clisso", "verify_hint": "clisso get <app>"},
        {"tool": "aws", "kind": "native", "catalog": true, "doc": "AWS access keys",
         "installed_path": "/usr/local/bin/aws", "wrapped": false, "native_category": "aws", "vault_secrets": 8},
        {"tool": "claude", "kind": "shim", "catalog": true, "doc": "Anthropic API key for Claude Code",
         "installed_path": "/Users/me/.local/bin/claude", "wrapped": false,
         "injects": [{"var": "ANTHROPIC_API_KEY", "vault_path": "wrap-claude/ANTHROPIC_API_KEY", "stored": false}]},
        {"tool": "gh", "kind": "shim", "catalog": true, "doc": "GitHub CLI OAuth token", "wrapped": true,
         "installed_path": "/opt/homebrew/bin/gh", "shim": "missing", "shim_detail": "shim symlink missing",
         "profile": "wrap-gh", "injects": [{"var": "GH_TOKEN", "vault_path": "wrap-gh/GH_TOKEN", "stored": true}],
         "sources": ["~/.config/gh/hosts.yml"], "token_command": "gh auth token"},
        {"tool": "docker", "kind": "native", "catalog": true, "doc": "Docker registry logins",
         "installed_path": "/usr/local/bin/docker", "wrapped": false, "native_category": "docker"},
        {"tool": "stripe", "kind": "shim", "catalog": true, "doc": "Stripe CLI API key", "wrapped": false},
        {"tool": "faketool", "kind": "shim", "catalog": false, "wrapped": true, "shim": "ok",
         "injects": [{"var": "FAKE", "vault_path": "wrap-faketool/FAKE", "stored": false}]}
      ]
    }
    """

    private func decode() throws -> ToolListing {
        try JSONDecoder().decode(ToolListing.self, from: Data(sample.utf8))
    }

    func testDecodesAndSections() throws {
        let listing = try decode()
        XCTAssertTrue(listing.shimDirOnPath)
        XCTAssertEqual(listing.tools.count, 7)
        // stripe is not installed, so it is not on this Mac's list.
        XCTAssertEqual(listing.installed.map(\.tool), ["clisso", "aws", "claude", "gh", "docker", "faketool"])
        XCTAssertEqual(listing.agents.map(\.tool), ["claude"])
        XCTAssertEqual(listing.others.map(\.tool), ["clisso", "aws", "gh", "docker", "faketool"])
        XCTAssertEqual(listing.wrapped.map(\.tool), ["clisso", "gh", "faketool"])
        XCTAssertEqual(listing.toWrap.map(\.tool), ["claude"], "native tools are never 'to wrap'")
        XCTAssertEqual(listing.broken.map(\.tool), ["gh"])
    }

    func testStateWords() throws {
        let listing = try decode()
        XCTAssertEqual(listing.tool(named: "clisso")?.stateLabel, "catching")
        XCTAssertEqual(listing.tool(named: "aws")?.stateLabel, "protected")
        XCTAssertEqual(listing.tool(named: "docker")?.stateLabel, "not protected")
        XCTAssertEqual(listing.tool(named: "claude")?.stateLabel, "not wrapped")
        XCTAssertEqual(listing.tool(named: "gh")?.stateLabel, "shim missing")
        XCTAssertEqual(listing.tool(named: "faketool")?.stateLabel, "wrapped")
        XCTAssertTrue(try XCTUnwrap(listing.tool(named: "aws")?.isProtected))
        XCTAssertFalse(try XCTUnwrap(listing.tool(named: "gh")?.isProtected), "a wrapped tool with a missing shim is not protected")
        XCTAssertFalse(try XCTUnwrap(listing.tool(named: "faketool")?.allStored))
    }

    func testShortDocDropsTheMechanism() throws {
        let listing = try decode()
        XCTAssertEqual(listing.tool(named: "aws")?.shortDoc, "AWS access keys")
        XCTAssertEqual(listing.tool(named: "gh")?.shortDoc, "GitHub CLI OAuth token")
        XCTAssertEqual(ToolRecord(tool: "x", kind: "shim").shortDoc, "")
    }

    func testAgentLabelsMatchTheScannerNames() throws {
        let listing = try decode()
        XCTAssertEqual(listing.tool(named: "claude")?.agentLabel, "Claude Code")
        XCTAssertNil(listing.tool(named: "gh")?.agentLabel)
        XCTAssertEqual(ToolRecord.agentLabels.count, 8)
        XCTAssertEqual(ToolRecord.agentTools.count, 10, "the website lists ten AI CLIs")
        XCTAssertTrue(ToolRecord(tool: "openai", kind: "shim").isAgent)
        XCTAssertNil(ToolRecord(tool: "openai", kind: "shim").agentLabel, "an API CLI keeps no cache to search")
    }

    func testStatusDecodesGuardAndSessions() throws {
        let json = """
        {"cli": {"version": "1.6.0"}, "vault": {"secrets_stored": 67, "backups_stored": 3},
         "guard": {"installed": true},
         "sessions": [{"profile": "aws-prod", "live": true, "mint": "clisso get prod"},
                      {"profile": "aws-stage", "expires_unix": 1789514660, "live": false, "mint": "clisso get stage"}]}
        """
        let status = try JSONDecoder().decode(CLIStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.guardStatus?.installed, true)
        XCTAssertEqual(status.sessions(mintedBy: "clisso").map(\.profile), ["aws-prod", "aws-stage"])
        XCTAssertNil(status.sessions?[0].expires, "an unknown stamp is nil, never 1970")
        XCTAssertNotNil(status.sessions?[1].expires)
        XCTAssertEqual(status.sessions(mintedBy: "gh"), [])
        // Older status output, without either field, still decodes.
        let old = try JSONDecoder().decode(CLIStatus.self, from: Data(#"{"vault": {"secrets_stored": 1}}"#.utf8))
        XCTAssertNil(old.guardStatus)
        XCTAssertEqual(old.sessions(mintedBy: "clisso"), [])
    }

    func testScanGroupsAgentCopiesByAgentAndArea() throws {
        func finding(_ id: String, _ path: String, agent: String?, area: String?, origin: String) -> String {
            let agentField = agent.map { #", "agent": "\#($0)""# } ?? ""
            let areaField = area.map { #", "cache_area": "\#($0)""# } ?? ""
            return #"{"record_type": "finding", "record_id": "\#(id)", "finding_type": "agent_cached_secret", "severity": "high", "#
                + #""file_path": "\#(path)", "evidence": "a copy", "remedy": "manual", "origin_path": "\#(origin)""#
                + agentField + areaField + "}"
        }
        let lines = [
            finding("a", "/h/.claude/file-history/x", agent: "Claude Code", area: "edit history", origin: "/h/p/.env"),
            finding("b", "/h/.claude/file-history/y", agent: "Claude Code", area: "edit history", origin: "/h/p/.env"),
            finding("c", "/h/.claude/projects/t.jsonl", agent: "Claude Code", area: "transcripts", origin: "/h/p/.env"),
            finding("d", "/h/.cursor/z", agent: nil, area: nil, origin: "/h/q/.env"),
            #"{"record_type": "finding", "record_id": "e", "finding_type": "env_file_present", "severity": "high", "#
                + #""file_path": "/h/p/.env", "evidence": "env", "remedy": "migrate", "fix_command": "jit migrate /h/p/.env"}"#,
            #"{"record_type": "scan_summary", "total_findings": 5, "risk_level": "high", "exposure_score": 50, "#
                + #""secrets_total": 2, "secrets_protected": 0, "secrets_migratable": 0, "files_scanned": 10}"#
        ]
        let report = try ScanReport.parse(Data(lines.joined(separator: "\n").utf8))
        XCTAssertEqual(report.agentCopies.count, 4)
        XCTAssertEqual(report.manual.count, 0, "cached copies leave the 'needs you' list; they have their own section")
        XCTAssertEqual(report.migratable.count, 1)
        let groups = report.agentCacheGroups
        XCTAssertEqual(groups.map(\.id), ["Claude Code·edit history", "Claude Code·transcripts", "an AI agent·cache"])
        XCTAssertEqual(groups[0].findings.count, 2)
        XCTAssertEqual(groups[0].files.count, 2)
        XCTAssertEqual(groups[0].origins, ["/h/p/.env"])
        XCTAssertEqual(report.agentCopies(in: "Claude Code"), 3)
        XCTAssertEqual(report.agentCopies(in: "Cursor"), 0)
    }
}

final class ToolKeyStateTests: XCTestCase {
    private func scan(_ findings: [String]) throws -> ScanReport {
        let summary = #"{"record_type": "scan_summary", "total_findings": 0, "risk_level": "low", "exposure_score": 0, "#
            + #""secrets_total": 0, "secrets_protected": 0, "secrets_migratable": 0, "files_scanned": 1}"#
        return try ScanReport.parse(Data((findings + [summary]).joined(separator: "\n").utf8))
    }

    private func finding(_ id: String, type: String = "exposed_secret", path: String, key: String? = nil, fix: String? = nil) -> String {
        let keyField = key.map { #", "key_name": "\#($0)""# } ?? ""
        let fixField = fix.map { #", "fix_command": "\#($0)""# } ?? ""
        return #"{"record_type": "finding", "record_id": "\#(id)", "finding_type": "\#(type)", "severity": "high", "#
            + #""file_path": "\#(path)", "evidence": "e", "remedy": "manual""# + keyField + fixField + "}"
    }

    func testListingDiscoveryWinsOverTheScan() {
        var gh = ToolRecord(tool: "gh", kind: "shim", installedPath: "/opt/homebrew/bin/gh")
        gh.keyFound = true
        gh.keySource = "gh auth token"
        XCTAssertEqual(gh.keyState(scan: nil), .found("gh auth token"))
        XCTAssertTrue(gh.keyState(scan: nil).found)
        XCTAssertFalse(gh.keyState(scan: nil).needsAction, "a keychain token is encrypted at rest; not a plaintext finding")
        XCTAssertTrue(ToolKeyState.found("/u/.zshrc").needsAction)
        gh.keyFound = false
        gh.keySource = nil
        XCTAssertEqual(gh.keyState(scan: nil), .none, "the listing looked and found nothing; no scan needed to say so")
    }

    func testShellConfigKeyNamesTheFileAndTheVaultPathMigrateWillUse() throws {
        var claude = ToolRecord(
            tool: "claude", kind: "shim", installedPath: "/u/.local/bin/claude",
            injects: [ToolInject(name: "ANTHROPIC_API_KEY", vaultPath: "wrap-claude/ANTHROPIC_API_KEY")]
        )
        let report = try scan([
            finding("a", type: "shell_config_secret", path: "/u/.zshrc", key: "ANTHROPIC_API_KEY"),
            finding("b", type: "exposed_secret", path: "/u/p/.env", key: "OPENAI_API_KEY")
        ])
        let key = try XCTUnwrap(claude.shellConfigKey(scan: report))
        XCTAssertEqual(key.file, "/u/.zshrc")
        XCTAssertEqual(key.name, "ANTHROPIC_API_KEY")
        XCTAssertEqual(key.vaultPath, "zshrc/ANTHROPIC_API_KEY", "migrate names the profile after the file, dot dropped")
        XCTAssertNil(claude.shellConfigKey(scan: nil))
        claude.keyFound = true
        claude.keySource = "~/.claude/.credentials.json"
        XCTAssertNil(claude.shellConfigKey(scan: report), "the tool's own key wins; jit wrap reads that one itself")
        let openai = ToolRecord(
            tool: "openai", kind: "shim", installedPath: "/u/.local/bin/openai",
            injects: [ToolInject(name: "OPENAI_API_KEY", vaultPath: "wrap-openai/OPENAI_API_KEY")]
        )
        XCTAssertNil(openai.shellConfigKey(scan: report), "an .env export is a migrate finding, not a shell config")
    }

    func testScanFindsAShellExportByTheVarTheToolReads() throws {
        let claude = ToolRecord(
            tool: "claude", kind: "shim", installedPath: "/u/.local/bin/claude",
            injects: [ToolInject(name: "ANTHROPIC_API_KEY", vaultPath: "wrap-claude/ANTHROPIC_API_KEY")]
        )
        XCTAssertEqual(claude.keyState(scan: nil), .unknown, "no discovery and no scan: not checked")
        let report = try scan([
            finding("a", type: "shell_config_secret", path: "/u/.zshrc", key: "ANTHROPIC_API_KEY"),
            finding("b", type: "wrappable_cli_token", path: "/u/.config/gh/hosts.yml", key: "oauth_token", fix: "jit wrap gh"),
            finding("c", type: "credential_file", path: "/u/.docker/config.json")
        ])
        XCTAssertEqual(claude.keyState(scan: report), .found("/u/.zshrc"))
        let gh = ToolRecord(tool: "gh", kind: "shim", installedPath: "/opt/homebrew/bin/gh")
        XCTAssertEqual(gh.keyState(scan: report), .found("/u/.config/gh/hosts.yml"), "a wrap finding names its tool by fix command")
        let docker = ToolRecord(tool: "docker", kind: "native", installedPath: "/usr/local/bin/docker", nativeCategory: "docker")
        XCTAssertEqual(docker.keyState(scan: report), .found("/u/.docker/config.json"))
        let git = ToolRecord(tool: "git", kind: "native", installedPath: "/usr/bin/git", nativeCategory: "git")
        XCTAssertEqual(git.keyState(scan: report), .none, "scanned, nothing of git's found")
        let aws = ToolRecord(tool: "aws", kind: "native", installedPath: "/u/aws", nativeCategory: "aws", vaultSecrets: 8)
        XCTAssertEqual(aws.keyState(scan: report), .protected)
        // A grant tool's key is the mount's file; migrate it first.
        var sops = ToolRecord(tool: "sops", kind: "grant", installedPath: "/opt/homebrew/bin/sops")
        sops.with = "sops"
        let withKey = try scan([finding("s", type: "sops_age_key", path: "/u/.config/sops/age/keys.txt")])
        XCTAssertEqual(sops.keyState(scan: withKey), .found("/u/.config/sops/age/keys.txt"))
        sops.vaultSecrets = 1
        XCTAssertTrue(sops.mountMigrated)
        XCTAssertEqual(sops.keyState(scan: withKey), .none, "once migrated the file is a mount; nothing left to find")
    }
}
