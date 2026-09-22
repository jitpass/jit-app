// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What an agent has recorded, counted the way its card says it: every
/// finding the scan placed in that agent's files — copies of vaulted
/// secrets, cached copies of confirmed credentials, and tokens found by
/// their format — not one type of them. The digest that counted only
/// `agent_cached_secret` said "no cached copies · all set" over 34 copies
/// in Claude Code's transcripts (2026-09-22).
public struct AgentExposure: Equatable, Sendable {
    /// Distinct vault entries with a copy in the agent's files.
    public var vaultSecrets = 0
    /// Files holding a copy of a vaulted secret, or a cached copy of a
    /// confirmed credential: what Clean Caches rewrites.
    public var copyFiles = 0
    public var copies = 0
    /// Tokens found by format, and the files holding them: what Redact
    /// rewrites.
    public var tokens = 0
    public var tokenFiles = 0
    /// The scanner's names for the areas the copies sit in, first seen first.
    public var areas: [String] = []
    /// The paths Redact would rewrite, for the agent's own Redact All.
    public var tokenPaths: [String] = []

    public var isEmpty: Bool {
        copies == 0 && tokens == 0
    }

    public var total: Int {
        copies + tokens
    }
}

public extension ScanReport {
    /// Every finding in one agent's files, by the scanner's own label.
    func findings(in agent: String) -> [ScanFinding] {
        findings.filter { $0.agent == agent && !$0.scaffolding }
    }

    func agentExposure(_ agent: String) -> AgentExposure {
        var exposure = AgentExposure()
        var keys = Set<String>(), copyPaths = Set<String>(), tokenPaths: [String] = [], seenToken = Set<String>()
        for f in findings(in: agent) {
            if f.isVaultCopy || f.isAgentCopy {
                exposure.copies += 1
                copyPaths.insert(f.filePath)
                if let key = f.keyName {
                    keys.insert(key)
                }
                if let area = f.cacheArea, !exposure.areas.contains(area) {
                    exposure.areas.append(area)
                }
            } else if f.isCacheShape {
                exposure.tokens += 1
                if seenToken.insert(f.filePath).inserted {
                    tokenPaths.append(f.filePath)
                }
            }
        }
        exposure.vaultSecrets = keys.count
        exposure.copyFiles = copyPaths.count
        exposure.tokenFiles = tokenPaths.count
        exposure.tokenPaths = tokenPaths
        return exposure
    }
}
