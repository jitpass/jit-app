// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// The Grants window's and the New Grant sheet's words, in one place. The
/// drawing they follow is the Grants Redesign mockup (design/standing-grants.md).
extension Format {
    // MARK: - The window

    /// The card's tier: the one word its eyebrow carries, with its dot.
    enum GrantTier {
        /// Served in the last minute.
        case serving
        /// A standing grant, not serving right now. Healthy.
        case standing
        /// A timed grant, not serving right now. Healthy.
        case active
        /// A standing grant with a rotated secret: only you can re-approve.
        case needsYou
        /// A timed grant whose process or app is gone; it ends on its own.
        case ending
    }

    static func grantTier(_ grant: GrantStatus, now: Date = Date()) -> GrantTier {
        if !grant.rotatedSecrets.isEmpty {
            return .needsYou
        }
        if let last = grant.lastServe, now.timeIntervalSince(last) < 60 {
            return .serving
        }
        if !grant.isStanding, !grant.rootAlive {
            return .ending
        }
        return grant.isStanding ? .standing : .active
    }

    static func grantEyebrow(_ tier: GrantTier) -> String {
        switch tier {
        case .serving: "Serving"
        case .standing: "Standing"
        case .active: "Active"
        case .needsYou: "Needs you"
        case .ending: "Ending"
        }
    }

    /// "3 grants", and what needs you when something does.
    static func grantsHeadline(_ grants: [GrantStatus]) -> String {
        if grants.isEmpty {
            return "Grants"
        }
        let rotated = grants.reduce(0) { $0 + $1.rotatedSecrets.count }
        var head = things(grants.count, "grant")
        if rotated > 0 {
            head += " · " + things(rotated, "secret") + (rotated == 1 ? " needs you" : " need you")
        }
        return head
    }

    static func grantsSubline(_ grants: [GrantStatus]) -> String {
        if grants.isEmpty {
            return "A grant lets one program use secrets unattended, with no Touch ID, until you revoke it."
        }
        if grants.contains(where: \.isStanding) {
            return "Each covers the secrets its profiles held when it was made. Revoking one deletes its key."
        }
        return "Each covers the secrets its profiles held when it was made, and ends at its deadline or when you revoke it."
    }

    static let grantsEmptyTitle = "Nothing runs unattended"
    static let grantsEmptyMessage = "Every program asks for Touch ID each time it uses a secret. " +
        "Make a grant when you want one to keep working while you are away."

    /// The row's first line after the program: its profiles, in mono.
    static func grantProfiles(_ grant: GrantStatus) -> String {
        "· " + grant.profiles.joined(separator: ", ")
    }

    static func grantName(_ grant: GrantStatus) -> String {
        grant.name ?? "pid \(grant.pid)"
    }

    /// "Every claude under iTerm2" or "pid 57394 only".
    static func grantCover(_ grant: GrantStatus) -> String {
        if let anchor = grant.anchor {
            return "Every \(grant.name ?? "copy") under \(anchor)"
        }
        return "pid \(grant.pid) only"
    }

    /// The row's one line of facts: cover, secrets, uses, and when it last
    /// served or when it ends.
    static func grantFact(_ grant: GrantStatus, now: Date = Date()) -> String {
        var parts = [grantCover(grant)]
        if !grant.isStanding, !grant.rootAlive {
            parts.append(grant.anchor.map { "\($0) quit, so this ends now" } ?? "that process exited, so this ends now")
            parts.append(grantUses(grant))
            return parts.joined(separator: " · ")
        }
        let total = grant.secrets?.count ?? 0
        let rotated = grant.rotatedSecrets.count
        if total > 0 {
            parts.append(rotated > 0 ? "\(total - rotated) of \(total) secrets" : things(total, "secret"))
        }
        parts.append(grantUses(grant))
        if grant.isStanding {
            if let last = grant.lastServe {
                parts.append("last " + grantAgo(last, now: now))
            }
        } else {
            parts.append("ends " + grantClock(grant.expires, now: now))
        }
        return parts.joined(separator: " · ")
    }

    static func grantUses(_ grant: GrantStatus) -> String {
        switch grant.serves ?? 0 {
        case 0: "unused"
        case 1: "used once"
        case let n: "used \(n) times"
        }
    }

    // MARK: - A rotated secret

    static func rotatedTitle(_ grant: GrantStatus) -> String {
        let total = grant.secrets?.count ?? grant.rotatedSecrets.count
        let n = grant.rotatedSecrets.count
        return "\(n) of \(total) secrets " + (n == 1 ? "was" : "were") + " rotated"
    }

    static func rotatedNote(_ grant: GrantStatus) -> String {
        let name = grant.name ?? "the program"
        let total = grant.secrets?.count ?? grant.rotatedSecrets.count
        let n = grant.rotatedSecrets.count
        let rest = total - n
        var note = n == 1
            ? "jit stopped serving it the moment its value changed, so \(name) asks for Touch ID for that one."
            : "jit stopped serving them the moment their values changed, so \(name) asks for Touch ID for those."
        if rest > 0 {
            note += " The other " + (rest == 1 ? "one is" : "\(rest) are") + " unaffected."
        }
        return note
    }

    static let rotatedFact = "Not served since it changed"

    // MARK: - Revoke

    static func revokeTitle(_ grant: GrantStatus) -> String {
        "Revoke \(grantName(grant))'s grant?"
    }

    static func revokeMessage(_ grant: GrantStatus) -> String {
        let profiles = grant.profiles.joined(separator: " and ")
        let tail = "\(profiles) go" + (grant.profiles.count == 1 ? "es" : "") +
            " back to asking for Touch ID each time \(grantName(grant)) uses " +
            (grant.profiles.count == 1 ? "it" : "them") + ". Making the grant again is a new Touch ID, not an undo."
        return grant.isStanding ? "This deletes the grant's key. " + tail : tail
    }

    static func revokedBanner(_ grant: GrantStatus) -> String {
        let head = "Revoked \(grantName(grant))'s grant to \(grant.profiles.joined(separator: ", "))."
        return grant.isStanding
            ? head + " Its key is deleted and it asks for Touch ID again from now."
            : head + " It asks for Touch ID again from now."
    }

    // MARK: - The sheet

    static let grantSheetTitle = "New Grant"
    static let grantFooterReady = "Touch ID follows. The service decides, not this app."
    static let grantFooterWaiting = "Waiting for Touch ID. The service is asking, not this app."
    static let grantFailure = "Nothing was granted. Everything you chose is still here."
    static let grantProfilesEmptyTitle = "No profiles on this Mac yet"
    static let grantProfilesEmptyNote = "A grant covers a profile's secrets, so there is nothing to grant yet."
    static let grantProfilesEmptyHint = "Protect a project's .env and its profile appears here."
    static let grantOneProcessDeadline = "A process dies at a reboot, so this always has a deadline. " +
        "Every copy can run until you revoke it."

    static func grantCoverHint(_ cover: GrantDraft.Cover) -> String {
        switch cover {
        case .oneProcess: "Only the process you pick below. Ends when it exits."
        case .everyCopy: "Every copy of a program started under a terminal or editor, now or later."
        }
    }

    /// "2 claudes run under iTerm2 now. Any started later are covered too."
    static func grantProgramHint(program: String, anchor: String, running: Int) -> String? {
        guard !program.isEmpty, !anchor.isEmpty else {
            return nil
        }
        let now = running == 0 ? "No \(program) runs under \(anchor) right now." : "\(running) \(program)" +
            (running == 1 ? " runs" : "s run") + " under \(anchor) now."
        return now + " Any started later are covered too."
    }

    static func grantProfilesHint(_ count: Int, matching: Int, filter: String) -> String {
        if !filter.isEmpty {
            return "\(matching) of \(count) match “\(filter)”. The folder under each name is what tells them apart."
        }
        return things(count, "profile") + " on this Mac"
    }

    /// The folder a profile is read from, as the row prints it.
    static func profileFolder(_ profile: DiscoveredProfile) -> String {
        profile.root.map(home) ?? "~/" + ProfileDiscovery.storeSubpath
    }

    static func profileSecrets(_ profile: DiscoveredProfile) -> String {
        "· " + things(profile.keys.count, "secret")
    }

    static func processFact(_ process: RunningProcess) -> String {
        var parts: [String] = []
        if !process.under.isEmpty {
            parts.append("under \(process.under)")
        }
        parts.append("running \(RunningProcess.age(process.elapsed))")
        parts.append("pid \(process.pid)")
        return parts.joined(separator: " · ")
    }

    static func grantEnds(_ term: GrantDraft.Term, now: Date = Date()) -> String? {
        term.ttl.map { "ends " + grantClock(now.addingTimeInterval($0), now: now) }
    }

    /// The three lines under the sheet: what the grant covers, how it ends,
    /// how to end it.
    static func grantNotes(_ draft: GrantDraft) -> [String] {
        let secrets = things(draft.secretCount, "secret")
        switch (draft.cover, draft.term) {
        case (.everyCopy, .untilRevoked):
            return [
                "No Touch ID for those \(secrets) while this grant exists, including after a restart or reboot.",
                "Covers them as they are now. If one is rotated, jit stops serving it and the Grants window says so.",
                "Revoke any time from the Grants window. That never asks, and it deletes this grant's key."
            ]
        case (.everyCopy, .hours):
            return [
                "Covers those \(secrets) as they are now. One that changes later stops being covered.",
                "Ends early if \(draft.anchorName ?? "the app") quits. Works across screen lock.",
                "Revoke any time from the Grants window. That never asks."
            ]
        case (.oneProcess, _):
            return [
                "That exact process only. Ends when it exits or at the deadline.",
                "Covers those \(secrets) as they are now. Works across screen lock.",
                "Revoke any time from the Grants window. That never asks."
            ]
        }
    }

    // MARK: - Time

    /// "today, 23:55", "tomorrow, 09:00", else "Wed 30 Sep, 15:55".
    static func grantClock(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let time = clock(date)
        if cal.isDate(date, inSameDayAs: now) {
            return "today, " + time
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow, " + time
        }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: date) + ", " + time
    }

    /// "a moment ago", "today, 11:04", "yesterday", "Monday", "3 Sep".
    static func grantAgo(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if now.timeIntervalSince(date) < 60 {
            return "a moment ago"
        }
        if cal.isDate(date, inSameDayAs: now) {
            return "today, " + clock(date)
        }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        let f = DateFormatter()
        f.dateFormat = now.timeIntervalSince(date) < 6 * 86400 ? "EEEE" : "d MMM"
        return f.string(from: date)
    }

    /// `/Users/me/app` for `~/app`, the inverse of `home`.
    static func expandHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "~" {
            return home
        }
        return path.hasPrefix("~/") ? home + path.dropFirst(1) : path
    }

    fileprivate static func things(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)" + (n == 1 ? "" : "s")
    }
}
