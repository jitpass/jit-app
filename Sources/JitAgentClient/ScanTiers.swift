// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What a finding asks of the reader. The scan window draws one card per
/// tier that has anything in it, and its filter one pill per tier, so a
/// tier with nothing in it is absent rather than a heading over the word
/// "nothing" (docs/design: windows.md, "a card's eyebrow carries its
/// tier").
public enum ScanTier: String, Sendable, CaseIterable, Identifiable {
    /// A deep scan's find: an exact copy of a secret already in the vault,
    /// still sitting in the open. First, because it is the one card whose
    /// secret jit already knows by name.
    case vaultCopies
    /// jit can move the value into the vault itself.
    case protect
    /// Only the person at the keyboard can: rotate it, or move it.
    case needsYou
    /// Verbatim copies an AI agent kept of a credential confirmed elsewhere.
    case agentCaches
    /// Real-looking values in test files and documentation.
    case testFixtures

    public var id: String {
        rawValue
    }
}

public extension ScanReport {
    /// One file per group, in the order the scan listed them. Agent caches
    /// group by agent and cache area instead (`agentCacheGroups`), so they
    /// are empty here and the window draws that tier from its own list.
    func groups(in tier: ScanTier) -> [ScanFileGroup] {
        switch tier {
        case .vaultCopies: ScanFileGroup.group(vaultCopies)
        case .protect: ScanFileGroup.group(migratable)
        case .needsYou: manualByFile
        case .agentCaches: []
        case .testFixtures: ScanFileGroup.group(scaffolding)
        }
    }

    /// Findings, not files: the number the filter pill and the footer show.
    func count(in tier: ScanTier) -> Int {
        if tier == .agentCaches {
            return agentCopies.count
        }
        return groups(in: tier).reduce(0) { $0 + $1.findings.count }
    }

    /// The tiers that have anything in them, in reading order. An empty
    /// list means a clean scan, and the window says so in a sentence
    /// rather than drawing four empty cards.
    var tiersPresent: [ScanTier] {
        ScanTier.allCases.filter { count(in: $0) > 0 }
    }

    /// Whether the window shows its filter at all: below two tiers there is
    /// nothing to narrow, and a filter over one card is furniture.
    var showsTierFilter: Bool {
        tiersPresent.count > 1
    }
}

public extension ScanFinding {
    /// `env_file_present` as `Env file present`.
    var typeLabel: String {
        Self.typeLabel(of: findingType)
    }

    /// The same rule for a type the view holds on its own.
    static func typeLabel(of type: String) -> String {
        let words = type.split(separator: "_").map(String.init)
        guard let first = words.first else {
            return type
        }
        return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
    }

    /// The token's name out of the scanner's evidence line: jit writes
    /// "value matches AWS Access Key ID's known token format" (and
    /// "contains a value matching …" for a shell history or an IaC file),
    /// and the name is the only part of that sentence a row has room for.
    /// Nil when the evidence says something else, and then the row prints
    /// it whole.
    var vendorName: String? {
        let tail = " known token format"
        guard evidence.hasSuffix(tail) else {
            return nil
        }
        let body = String(evidence.dropLast(tail.count))
        guard let lead = ["value matches ", "a value matching "].first(where: { body.contains($0) }),
              let start = body.range(of: lead, options: .backwards)
        else {
            return nil
        }
        var name = String(body[start.upperBound...]).trimmingCharacters(in: .whitespaces)
        // jit makes the vendor possessive to read as English; the row wants
        // the name. "Database connection string with embedded credentials's"
        // keeps its trailing s, which is why the apostrophe leads here.
        if name.hasSuffix("'s") {
            name = String(name.dropLast(2))
        } else if name.hasSuffix("'") {
            name = String(name.dropLast())
        }
        return name.isEmpty ? nil : name
    }

    /// What one finding contributes to a row or a sheet line: the token's
    /// name when the scanner matched a format, its own evidence otherwise.
    var shortEvidence: String {
        vendorName ?? evidence
    }
}

public extension ScanFileGroup {
    /// The row's one fact, in one clause, ellipsised by the view and never
    /// wrapped (windows.md, "Rows"). One flagged line reads as itself; a
    /// file with several names the first three and counts the rest, and
    /// the whole list opens in a sheet.
    var fact: String {
        guard let first = findings.first else {
            return ""
        }
        if findings.count == 1 {
            var parts: [String] = []
            if let line = first.line {
                parts.append("line \(line)")
            }
            if first.vendorName == nil {
                parts.append(first.typeLabel)
            }
            parts.append(first.shortEvidence)
            return parts.joined(separator: " · ")
        }
        let names = findings.prefix(3).map(\.shortEvidence)
        let rest = findings.count - names.count
        let list = names.joined(separator: ", ") + (rest > 0 ? " and \(rest) more" : "")
        return "\(findings.count) flagged lines · " + list
    }

    /// The line a row's Open jumps to: the first one the scanner numbered.
    var firstLine: Int? {
        findings.compactMap(\.line).first
    }
}
