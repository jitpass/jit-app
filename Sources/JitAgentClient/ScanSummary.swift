// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The record that closes a scan's stream: its totals, score and depth.
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
    /// Findings left out because the user marked them reviewed (`jit scan
    /// review`, schema 0.25.0).
    public var reviewed: Int?
    public var schemaVersion: String?

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
        case reviewed
        case schemaVersion = "schema_version"
    }
}
