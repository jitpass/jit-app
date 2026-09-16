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

    static func doctorSummary(_ report: DoctorReport) -> String {
        var parts: [String] = []
        if let tool = report.tool {
            parts.append("jit \(tool.version)" + (tool.signature.map { " · \($0)" } ?? ""))
        }
        if let profiles = report.profilesChecked, let secrets = report.secretsChecked {
            parts.append("\(profiles) profiles, \(secrets) secrets checked")
        }
        return parts.joined(separator: " · ")
    }

    /// "2026-09-16" for a file name.
    static func dateStamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// 300 -> "5m", 3600 -> "1h": the form `jit service ttl` prints and takes.
    static func duration(seconds: Int64?) -> String {
        guard let seconds, seconds > 0 else {
            return ""
        }
        if seconds % 3600 == 0 {
            return "\(seconds / 3600)h"
        }
        return "\(seconds / 60)m"
    }

    /// An agent error as one readable sentence.
    static func error(_ error: Error) -> String {
        switch error as? AgentClientError {
        case let .agent(message): message
        case .notRunning: "the service is not running"
        case .timeout: "no answer from the service; the prompt may still be on screen"
        default: "\(error)"
        }
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
