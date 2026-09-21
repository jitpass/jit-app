// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The one notification after a scheduled whole-Mac scan: what it found
/// that the previous one had not. A run that changes nothing is silent.
public struct ScanNotice: Equatable, Sendable {
    public var title: String
    public var body: String
}

public enum ScanNotices {
    /// "Sunday's scan found 2 secrets in the open, and 7 cached copies" /
    /// "~/notion/.env, ~/.aws/old, and 7 copies in Claude Code's
    /// transcripts. Click to open Findings." nil when nothing is new.
    /// `home` is the user's home directory, so paths read as `~/…`.
    public static func make(
        new: [ScanFinding],
        at: Date,
        home: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> ScanNotice? {
        let files = new.filter { !$0.isAgentCopy }
        let copies = new.filter(\.isAgentCopy)
        guard !files.isEmpty || !copies.isEmpty else {
            return nil
        }
        let day = ScanWording.dayWord(at, now: now, calendar: calendar, locale: locale)
        let scan = day.prefix(1).uppercased() + day.dropFirst() + "'s scan found "
        let secrets = "\(files.count) secret" + (files.count == 1 ? "" : "s") + " in the open"
        let cached = "\(copies.count) cached cop" + (copies.count == 1 ? "y" : "ies")
        let title: String = switch (files.isEmpty, copies.isEmpty) {
        case (false, true): scan + secrets
        case (true, false): scan + "\(copies.count) new cached cop" + (copies.count == 1 ? "y" : "ies") + " of your secrets"
        default: scan + secrets + ", and " + cached
        }

        var parts: [String] = []
        var seen: Set<String> = []
        let paths = files.map(\.filePath).filter { seen.insert($0).inserted }
        parts += paths.prefix(2).map { abbreviate($0, home: home) }
        if paths.count > 2 {
            parts.append("\(paths.count - 2) more")
        }
        var order: [String] = []
        var byAgent: [String: (count: Int, areas: [String])] = [:]
        for copy in copies {
            let agent = copy.agent ?? "an AI agent"
            if byAgent[agent] == nil {
                order.append(agent)
                byAgent[agent] = (0, [])
            }
            byAgent[agent]?.count += 1
            if let area = copy.cacheArea, byAgent[agent]?.areas.contains(area) == false {
                byAgent[agent]?.areas.append(area)
            }
        }
        for agent in order {
            guard let entry = byAgent[agent] else {
                continue
            }
            let n = "\(entry.count) cop" + (entry.count == 1 ? "y" : "ies")
            let place = entry.areas.isEmpty ? "\(agent)'s cache" : "\(agent)'s " + entry.areas.joined(separator: " and ")
            parts.append((parts.isEmpty ? "" : "and ") + n + " in " + place)
        }
        return ScanNotice(title: title, body: parts.joined(separator: ", ") + ". Click to open Findings.")
    }

    static func abbreviate(_ path: String, home: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

public extension ScanWording {
    /// The day a run happened, as a person names it: "today",
    /// "yesterday", "Sunday" inside a week, "Jan 17" beyond it.
    static func dayWord(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        if abs(now.timeIntervalSince(date)) < 7 * 86400 {
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
            return formatter.string(from: date)
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "d MMM" : "d MMM yyyy")
        return formatter.string(from: date)
    }
}
