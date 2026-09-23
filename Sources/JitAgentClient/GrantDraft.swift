// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What the New Grant sheet is filling in: the sentence the disclosed Touch
/// ID will ask, one blank at a time. Pure state, so the rules for when the
/// sentence is complete, what is missing, and what the sentence says live
/// where a test can hold them rather than in the view.
public struct GrantDraft: Sendable, Equatable {
    /// One process (a pid, always with a deadline) or every copy of a
    /// program under an app (standing by default).
    public enum Cover: Sendable, Equatable, Hashable {
        case oneProcess
        case everyCopy
    }

    /// The For segment: a duration, or until revoked (every copy only).
    public enum Term: Sendable, Equatable, Hashable {
        case hours(Int)
        case untilRevoked

        public var ttl: TimeInterval? {
            switch self {
            case let .hours(hours): TimeInterval(hours) * 3600
            case .untilRevoked: nil
            }
        }
    }

    public var cover: Cover
    /// One process: the picked pid, and how it reads ("claude · pid 57394").
    public var pid: Int32?
    public var processName: String?
    /// Every copy: the typed program name and the chosen app.
    public var program: String
    public var anchorPID: Int32?
    public var anchorName: String?
    public var profiles: [DiscoveredProfile]
    public var term: Term

    public init(
        cover: Cover = .everyCopy, pid: Int32? = nil, processName: String? = nil, program: String = "",
        anchorPID: Int32? = nil, anchorName: String? = nil, profiles: [DiscoveredProfile] = [], term: Term = .untilRevoked
    ) {
        self.cover = cover
        self.pid = pid
        self.processName = processName
        self.program = program
        self.anchorPID = anchorPID
        self.anchorName = anchorName
        self.profiles = profiles
        self.term = term
    }

    /// The durations the sheet offers, and until revoked where a copy can
    /// outlive a reboot.
    public static let durations = [1, 8, 24, 168]

    public var terms: [Term] {
        var out = Self.durations.map(Term.hours)
        if cover == .everyCopy {
            out.append(.untilRevoked)
        }
        return out
    }

    /// The program the sentence names, trimmed.
    public var programName: String {
        program.trimmingCharacters(in: .whitespaces)
    }

    /// Why the button is off, in the footer's words; nil when the sentence
    /// is complete. The first blank in reading order.
    public var missing: String? {
        switch cover {
        case .oneProcess:
            if pid == nil {
                return "Pick the process to cover"
            }
        case .everyCopy:
            if programName.isEmpty || anchorPID == nil {
                return "Name a program and pick its app"
            }
        }
        if profiles.isEmpty {
            return "Tick at least one profile"
        }
        if cover == .oneProcess, term == .untilRevoked {
            return "One process always has a deadline"
        }
        return nil
    }

    public var isComplete: Bool {
        missing == nil
    }

    /// The sentence, as parts the view sets in bold or in grey: a filled
    /// blank is `.value`, an empty one `.blank`, the rest `.text`.
    public enum Part: Sendable, Equatable {
        case text(String)
        case value(String)
        case blank(String)
    }

    public var sentence: [Part] {
        var parts: [Part] = [.text("Let ")]
        switch cover {
        case .oneProcess:
            if let pid, let processName {
                parts.append(.value("\(processName) · pid \(pid)"))
            } else {
                parts.append(.blank("a process"))
            }
        case .everyCopy:
            parts.append(programName.isEmpty ? .blank("a program") : .value(programName))
            parts.append(.text(" under "))
            parts.append(anchorName.map { .value($0) } ?? .blank("an app"))
        }
        parts.append(.text(" use "))
        if profiles.isEmpty {
            parts.append(.blank("some secrets"))
        } else {
            let names = profiles.map(\.name)
            for (index, name) in names.enumerated() {
                if index > 0 {
                    parts.append(.text(index == names.count - 1 ? " and " : ", "))
                }
                parts.append(.value(name))
            }
        }
        parts.append(.text(", "))
        parts.append(.value(Self.termPhrase(term)))
        parts.append(.text("."))
        return parts
    }

    /// The sentence as plain text, for a test or a log line.
    public var sentenceText: String {
        sentence.map { part in
            switch part {
            case let .text(s), let .value(s), let .blank(s): s
            }
        }.joined()
    }

    public static func termPhrase(_ term: Term) -> String {
        switch term {
        case .untilRevoked: "until you revoke it"
        case let .hours(hours) where hours % 24 == 0 && hours > 24: "for \(hours / 24) days"
        case .hours(24): "for 24 hours"
        case .hours(1): "for 1 hour"
        case let .hours(hours): "for \(hours) hours"
        }
    }

    /// The pill label for a term.
    public static func termLabel(_ term: Term) -> String {
        switch term {
        case .untilRevoked: "Until revoked"
        case let .hours(hours) where hours % 24 == 0 && hours > 24: "\(hours / 24)d"
        case let .hours(hours): "\(hours)h"
        }
    }

    /// The number of secrets the ticked profiles hold, counted by key.
    public var secretCount: Int {
        profiles.reduce(0) { $0 + $1.keys.count }
    }

    public var grantProfiles: [GrantProfile] {
        profiles.map(\.grantProfile)
    }
}
