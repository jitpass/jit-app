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

    static func scanSummary(_ s: ScanSummary) -> String {
        "\(s.totalFindings) findings · \(s.secretsProtected) of \(s.secretsTotal) secrets protected · \(s.filesScanned) files"
    }

    static func event(_ event: SessionEvent) -> String {
        let who = event.by.map { String($0.prefix(28)) } ?? "?"
        return "\(event.kind) by \(who) · \(clock(event.date))"
    }

    /// "  claude → jamf, aws-ci  until 17:42", indented to sit under the Grants row.
    static func grant(_ grant: GrantStatus) -> String {
        let holder = grant.name ?? "pid \(grant.pid)"
        let profiles = grant.profiles.joined(separator: ", ")
        return "  \(holder) → \(profiles)  until \(clock(grant.expires))"
    }
}
