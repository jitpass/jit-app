// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

enum Format {
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func clock(_ date: Date) -> String { clock.string(from: date) }

    static func event(_ event: SessionEvent) -> String {
        let who = event.by.map { String($0.prefix(28)) } ?? "?"
        return "\(event.kind) by \(who) · \(clock(event.date))"
    }
}
