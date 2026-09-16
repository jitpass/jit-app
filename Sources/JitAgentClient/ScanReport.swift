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
    public var evidence: String
    public var remedy: String
    public var fixCommand: String?
    public var archived: Bool
    /// The file is test scaffolding (a *_test.go, a testdata/ path) or the
    /// value is a documented example. The scanner still counts them, and the
    /// score includes them, but a reader wants them set apart.
    public var testFixture: Bool
    public var sourceExample: Bool

    enum CodingKeys: String, CodingKey {
        case id = "record_id"
        case findingType = "finding_type"
        case severity
        case filePath = "file_path"
        case evidence
        case remedy
        case fixCommand = "fix_command"
        case archived
        case testFixture = "test_fixture"
        case sourceExample = "source_example"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        findingType = try container.decode(String.self, forKey: .findingType)
        severity = try container.decode(String.self, forKey: .severity)
        filePath = try container.decode(String.self, forKey: .filePath)
        evidence = try container.decode(String.self, forKey: .evidence)
        remedy = try container.decode(String.self, forKey: .remedy)
        fixCommand = try container.decodeIfPresent(String.self, forKey: .fixCommand)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        testFixture = try container.decodeIfPresent(Bool.self, forKey: .testFixture) ?? false
        sourceExample = try container.decodeIfPresent(Bool.self, forKey: .sourceExample) ?? false
    }

    /// True when `jit migrate` can fix it; false means only the user can.
    public var migratable: Bool {
        remedy == "migrate"
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

    enum CodingKeys: String, CodingKey {
        case totalFindings = "total_findings"
        case riskLevel = "risk_level"
        case exposureScore = "exposure_score"
        case secretsTotal = "secrets_total"
        case secretsProtected = "secrets_protected"
        case secretsMigratable = "secrets_migratable"
        case filesScanned = "files_scanned"
        case scanTime = "scan_time"
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

    public var manual: [ScanFinding] {
        findings.filter { !$0.migratable && !$0.scaffolding }
    }

    public var scaffolding: [ScanFinding] {
        findings.filter(\.scaffolding)
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
