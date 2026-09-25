// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The New AI Job sheet's state, and everything about it worth a test: the
/// typed command split into arguments, what is still missing (the footer's
/// words while the button is off), the sentence at the top, and the
/// `JobSpec` it proposes. The service decides whether the job is allowed;
/// this only says whether there is enough to ask it.
public struct JobDraft: Sendable, Equatable {
    public var name = ""
    public var folder = ""
    public var command = ""
    public var profile: String?
    /// Variables whose values may appear in the output.
    public var shown: Set<String> = []
    public var ask: JobAsk = .eachTime
    public var output = ""
    /// Set when the draft came from an agent's proposal.
    public var proposal: JobProposal?

    public init() {}

    /// A draft pre-filled from an agent's proposal. It opens at each-time
    /// whatever the agent asked for: only the human chooses unattended.
    public init(proposal: JobProposal) {
        name = proposal.name
        folder = proposal.spec.dir
        command = JobDraft.join(proposal.spec.argv)
        profile = proposal.spec.profile?.name
        shown = Set(proposal.spec.shown ?? [])
        ask = .eachTime
        output = proposal.spec.outputs?.first ?? ""
        self.proposal = proposal
    }

    public var argv: [String] {
        JobDraft.split(command)
    }

    /// The footer's words for the first thing the sheet still needs, or nil.
    public var missing: String? {
        if folder.isEmpty {
            return "Choose the folder the job runs in"
        }
        if argv.isEmpty {
            return "Type the command, as you would in a terminal in that folder"
        }
        if name.isEmpty {
            return "Name the job"
        }
        if !JobDraft.isValidName(name) {
            return "Name it with lowercase letters, digits and dashes"
        }
        return nil
    }

    public var isComplete: Bool {
        missing == nil
    }

    /// The name jit accepts: lowercase letters, digits and dashes, starting
    /// with a letter or digit, at most 40. The service checks again.
    public static func isValidName(_ name: String) -> Bool {
        guard let first = name.first, name.count <= 40, first.isLetter || first.isNumber else {
            return false
        }
        return name.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" }
    }

    /// A job name from a folder: "custom_scripts/notion" → "notion".
    public static func suggestedName(folder: String) -> String {
        let base = (folder as NSString).lastPathComponent.lowercased()
        let mapped = base.map { ($0.isASCII && ($0.isLetter || $0.isNumber)) ? $0 : "-" }
        let trimmed = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(40))
    }

    public func spec(pathEnv: String, home: String) -> JobSpec {
        JobSpec(
            dir: folder, argv: argv,
            profile: profile.map { GrantProfile(name: $0, root: folder) },
            ask: ask.rawValue,
            shown: shown.isEmpty ? nil : shown.sorted(),
            outputs: output.isEmpty ? nil : [output],
            pathEnv: pathEnv, home: home
        )
    }

    // MARK: - Arguments

    /// Splits a typed command the way a shell would for the cases a job
    /// needs: whitespace separates, single quotes are literal, double quotes
    /// group, a backslash escapes the next character. No expansion of any
    /// kind: what is typed is what runs, and what the service fingerprints.
    public static func split(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for ch in line {
            if escaped {
                current.append(ch)
                escaped = false
                inWord = true
                continue
            }
            if ch == "\\", quote != "'" {
                escaped = true
                continue
            }
            if let open = quote {
                if ch == open {
                    quote = nil
                } else {
                    current.append(ch)
                }
                continue
            }
            if ch == "'" || ch == "\"" {
                quote = ch
                inWord = true
            } else if ch.isWhitespace {
                if inWord {
                    out.append(current)
                    current = ""
                    inWord = false
                }
            } else {
                current.append(ch)
                inWord = true
            }
        }
        if inWord {
            out.append(current)
        }
        return out
    }

    /// The inverse of `split` for display: a plain word bare, anything else
    /// single-quoted.
    public static func join(_ argv: [String]) -> String {
        argv.map { word in
            let plain = !word.isEmpty && word.allSatisfy { $0.isLetter || $0.isNumber || "-_./=:@%+,".contains($0) }
            return plain ? word : "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }
}
