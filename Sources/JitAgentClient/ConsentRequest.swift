// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One disclosed challenge the agent has parked with this app, read out of
/// its `pending` event into the facts the sheet shows. Every fact here is
/// the agent's own: the wording is the exact sentence the Touch ID would
/// carry, the command line and launcher are kernel-derived (or marked as a
/// scan), and nothing the requesting process claimed about itself is used.
public struct ConsentRequest: Sendable, Equatable, Identifiable {
    public let id: String
    public let event: SessionEvent

    public init?(event: SessionEvent) {
        guard event.kind == "pending", let id = event.consentID, !id.isEmpty else {
            return nil
        }
        self.id = id
        self.event = event
    }

    /// The sentence the human decides by, as the Touch ID would show it.
    public var headline: String {
        event.cause ?? "a program asks to use a credential"
    }

    /// The program's name: the basename of the command's first word, or the
    /// pid when the agent could not name it.
    public var program: String {
        if let first = event.by?.split(separator: " ", maxSplits: 1).first, !first.isEmpty {
            return String(first.split(separator: "/").last ?? first)
        }
        if let pid = event.byPID {
            return "a process (pid \(pid))"
        }
        return "a program"
    }

    public var command: String? {
        event.by
    }

    public var pid: Int32? {
        event.byPID
    }

    public var launchedBy: String? {
        event.launchedBy
    }

    /// True when the identity came from scanning running processes (a mount
    /// reader), which a process running as you could fake, rather than from
    /// the kernel naming the socket peer.
    public var identifiedByScan: Bool {
        event.byLikely ?? false
    }

    /// What kind of authority the request is for, from the agent's op.
    public var purpose: String {
        switch event.op {
        case "grant_create": "create a grant: unattended access until a deadline"
        case "grant_extend": "extend a grant's deadline"
        default: "use a credential once, remembered until the vault locks"
        }
    }

    /// How many times this same request was already refused this session,
    /// read from the agent's own "(refused N times)" marker. Zero when the
    /// marker is absent; the headline still shows it either way.
    public var priorRefusals: Int {
        guard let cause = event.cause else {
            return 0
        }
        if cause.contains("(refused once)") {
            return 1
        }
        guard let range = cause.range(of: #"\(refused (\d+) times\)"#, options: .regularExpression) else {
            return 0
        }
        let digits = cause[range].filter(\.isNumber)
        return Int(digits) ?? 0
    }

    public var date: Date {
        event.date
    }
}
