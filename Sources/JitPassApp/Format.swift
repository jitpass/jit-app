// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

enum Format {
    static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
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
