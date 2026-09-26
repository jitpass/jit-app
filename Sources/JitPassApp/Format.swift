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

    /// A project's origin for the orphans list: the file its secrets were
    /// migrated from. jit's own phrase for none is "no recorded origin
    /// (pre-provenance, or set directly)", which explains jit to itself;
    /// the row says what is missing and leaves it there.
    static func orphanOrigin(_ group: VaultOrphanGroup) -> String {
        switch group.origins.count {
        case 0: "origin not recorded"
        case 1: home(group.origins[0])
        default: "\(group.origins.count) origins"
        }
    }

    /// `env_file_present` as `Env file present`. The rule lives with the
    /// finding, where a test can hold it.
    static func findingType(_ type: String) -> String {
        ScanFinding.typeLabel(of: type)
    }

    /// The last path component, which is what tells two rows apart.
    static func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// The folder under it, home-relative and without its trailing slash:
    /// the row prints the name first and this after it, in mono.
    static func parentFolder(_ path: String) -> String {
        let parent = home((path as NSString).deletingLastPathComponent)
        return parent.isEmpty ? "" : parent
    }

    /// The window's headline: for the whole Mac, what is safe — the
    /// vault's own count, the one number that needs no explanation — with
    /// the to-do lines under it saying what is not (ScanTodo). A folder
    /// scan, or a Mac whose vault jit cannot see, leads with its findings.
    static func scanHeadline(_ s: ScanSummary, wholeMac: Bool, secretsStored: Int?) -> String {
        guard wholeMac, let stored = secretsStored else {
            return "\(s.totalFindings) finding" + (s.totalFindings == 1 ? "" : "s")
        }
        switch stored {
        case 0: return "Nothing in your vault yet"
        case 1: return "1 secret in your vault"
        default: return "\(stored) secrets in your vault"
        }
    }

    /// The footer: how much the scan read. Every count is already on its
    /// filter pill, so the footer does not count them again. (The header's
    /// second line is `ScanWording`'s: it carries the schedule.)
    static func scanFooter(_ report: ScanReport) -> String {
        report.summary.filesScanned.formatted(.number) + " files read"
    }

    /// A tier's word, for its card's eyebrow and its filter pill.
    static func tierLabel(_ tier: ScanTier) -> String {
        switch tier {
        case .vaultCopies: "Vault copies"
        case .protect: "Protect"
        case .needsYou: "Needs you"
        case .agentCaches: "Agent caches"
        case .testFixtures: "Test fixtures"
        }
    }

    /// A tier's card title: what the reader is looking at, counted once.
    static func tierTitle(_ tier: ScanTier, files: Int) -> String {
        let n = "\(files) file" + (files == 1 ? "" : "s")
        switch tier {
        case .vaultCopies:
            if files == 1 {
                return "1 file holds a copy of a vaulted secret"
            }
            return n + " hold copies of vaulted secrets"
        case .protect: return "jit can move " + (files == 1 ? "this one" : "these") + " into the vault"
        case .needsYou: return files == 1 ? "Only you can fix this one" : "Only you can fix these"
        case .agentCaches: return n + " of agent caches hold copies"
        case .testFixtures: return n + " hold real-looking examples"
        }
    }

    /// What the tier is, and what the choice costs.
    static func tierNote(_ tier: ScanTier) -> String {
        switch tier {
        case .vaultCopies: "Rotate each secret, then delete the copy."
        case .protect: "A decoy takes each value's place. Every file is backed up first."
        case .needsYou: "jit can't rewrite these safely. Rotate each value, or move it yourself."
        case .agentCaches: ScanReportView.agentNote
        case .testFixtures: "Real-looking values in test files and examples. They don't count toward the score. Check they are not live."
        }
    }

    /// The lines sheet's title: the file, and how many lines it flagged.
    static func linesTitle(_ group: ScanFileGroup) -> String {
        let n = group.findings.count
        return "\(n) flagged line" + (n == 1 ? "" : "s") + " in " + fileName(group.filePath)
    }

    /// The protected-secrets tally is machine-wide (it reads the vault), so
    /// The findings count leads only for a whole-Mac scan; a folder scan's
    /// header already leads with it. A zero file count is not a fact
    /// worth printing.
    static func scanSummary(_ s: ScanSummary, wholeMac: Bool) -> String {
        var parts = wholeMac ? ["\(s.totalFindings) finding\(s.totalFindings == 1 ? "" : "s")"] : []
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

    /// "2 months ago", "yesterday", "in 3 days".
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// "expires in 2 hours" / "expired 2 hours ago", for a captured session.
    static func expiry(_ date: Date, now: Date = Date()) -> String {
        (date > now ? "expires " : "expired ") + ago(date, now: now)
    }

    /// "16 Sep 13:58" for a list that spans days, "13:58" for one that
    /// does not: the date on every row, not a header the eye has to find.
    static func stamp(_ date: Date, withDay: Bool) -> String {
        guard withDay else {
            return clock(date)
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date) + " " + clock(date)
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
}
