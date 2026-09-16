// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

enum Format {
    static func clock(_ date: Date) -> String {
        SessionState.clock(date)
    }

    /// `/Users/me/app/.env` as `~/app/.env`.
    static func home(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// `env_file_present` as `Env file present`.
    static func findingType(_ type: String) -> String {
        let words = type.split(separator: "_").map(String.init)
        guard let first = words.first else {
            return type
        }
        return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
    }

    /// The protected-secrets tally is machine-wide (it reads the vault), so
    /// it is shown only for a whole-Mac scan; a folder scan would put a
    /// global number under a local scope. A zero file count is not a fact
    /// worth printing.
    static func scanSummary(_ s: ScanSummary, wholeMac: Bool) -> String {
        var parts = ["\(s.totalFindings) findings"]
        if wholeMac {
            parts.append("\(s.secretsProtected) of \(s.secretsTotal) secrets protected")
        }
        if s.filesScanned > 0 {
            parts.append("\(s.filesScanned) files")
        }
        return parts.joined(separator: " · ")
    }

    static func event(_ event: SessionEvent) -> String {
        AuditReport.title(for: event) + " · " + clock(event.date)
    }

    /// "  claude → jamf, aws-ci  until 17:42", indented to sit under the Grants row.
    static func grant(_ grant: GrantStatus) -> String {
        let holder = grant.name ?? "pid \(grant.pid)"
        let profiles = grant.profiles.joined(separator: ", ")
        return "  \(holder) → \(profiles)  until \(clock(grant.expires))"
    }
}
