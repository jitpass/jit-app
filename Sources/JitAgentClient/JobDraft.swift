// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The New AI Job sheet's state, and everything about it worth a test: the
/// command split into arguments, what is still missing (the footer's words
/// while the button is off), the sentence at the top, and the `JobSpec` it
/// proposes. The sheet starts from a profile, as New Grant does: the job
/// runs in the profile's folder unless a folder inside it is chosen, where
/// the script is; a profile from the global store has no folder, so one is
/// always chosen for it. The service decides whether the job is allowed;
/// this only says whether there is enough to ask it.
public struct JobDraft: Sendable, Equatable {
    public var name = ""
    public var folder = ""
    public var command = ""
    public var profile: String?
    /// The profile is from `~/.jit/profiles`, so it names no folder and the
    /// job's folder is chosen.
    public var global = false
    /// The folder the profile is read from; the job's `folder` starts here
    /// and may be one inside it. Nil for a global profile.
    public var profileRoot: String?
    /// The name was made from the script and follows it until edited.
    public var nameSuggested = true
    /// Variables whose values may appear in the output.
    public var shown: Set<String> = []
    public var ask: JobAsk = .eachTime
    /// Not set from the app: `jit job allow --output` only. An edit keeps
    /// what the job was approved with; a proposal's is dropped, so nothing
    /// is approved that the sheet did not show.
    public var output = ""
    /// Set when the draft came from an agent's proposal.
    public var proposal: JobProposal?
    /// Set when the draft edits an approved job: what it was approved as.
    /// Approving it again replaces the job under the same name.
    public var editing: JobStatus?

    public init() {}

    /// A draft pre-filled from an agent's proposal. It opens at each-time
    /// whatever the agent asked for: only the human chooses unattended.
    public init(proposal: JobProposal) {
        name = proposal.name
        folder = proposal.spec.dir
        command = JobDraft.join(proposal.spec.argv)
        profile = proposal.spec.profile?.name
        global = proposal.spec.profile.map { ($0.root ?? "").isEmpty } ?? false
        profileRoot = global ? nil : proposal.spec.profile?.root
        nameSuggested = false
        shown = Set(proposal.spec.shown ?? [])
        ask = .eachTime
        self.proposal = proposal
    }

    /// A draft that edits `job`: everything as it was approved, and the
    /// name fixed, since renaming is a new job.
    public init(editing job: JobStatus) {
        name = job.name
        folder = job.dir
        command = JobDraft.join(job.argv)
        profile = job.profile
        global = job.profileGlobal == true
        profileRoot = global ? nil : job.profileRoot ?? job.dir
        shown = Set((job.secrets ?? []).filter(\.isShown).map(\.name))
        ask = JobAsk(rawValue: job.ask ?? "") ?? .eachTime
        output = job.outputs?.first ?? ""
        nameSuggested = false
        editing = job
    }

    /// What an edit changes from the approved job, in the sheet's words.
    /// Empty when nothing has changed yet.
    public var changes: [String] {
        guard let job = editing else {
            return []
        }
        var out: [String] = []
        if profile != job.profile {
            out.append("profile " + (profile ?? "none"))
        } else if folder != job.dir {
            out.append("runs in " + (folder as NSString).lastPathComponent)
        }
        if argv != job.argv {
            out.append("runs " + command)
        }
        let was = Set((job.secrets ?? []).filter(\.isShown).map(\.name))
        let names = Set((job.secrets ?? []).map(\.name))
        if profile == job.profile, folder == job.dir {
            for name in names.sorted() where shown.contains(name) != was.contains(name) {
                out.append(name + (shown.contains(name) ? " shown" : " hidden"))
            }
        }
        if ask.rawValue != (job.ask ?? JobAsk.eachTime.rawValue) {
            out.append(ask == .eachTime ? "asks each time" : "runs without asking")
        }
        return out
    }

    public var argv: [String] {
        JobDraft.split(command)
    }

    /// Picks a profile: its folder becomes the job's, and what was chosen
    /// for the last profile's folder is dropped.
    public mutating func choose(profile picked: DiscoveredProfile) {
        profile = picked.name
        global = picked.root == nil
        profileRoot = picked.root
        folder = picked.root ?? ""
        command = ""
        shown = []
        if nameSuggested {
            name = ""
        }
    }

    /// Picks the folder the script is in, which drops the command chosen
    /// for the last one.
    public mutating func choose(folder picked: String) {
        guard picked != folder else {
            return
        }
        folder = picked
        command = ""
        if nameSuggested {
            name = ""
        }
    }

    /// Back to choosing a profile. An edit keeps the job it edits and its
    /// name; the ask is kept either way.
    public func cleared() -> JobDraft {
        var draft = JobDraft()
        draft.ask = ask
        if let job = editing {
            draft.editing = job
            draft.name = job.name
            draft.nameSuggested = false
        }
        return draft
    }

    /// Picks a script: the command, and the name made from it unless the
    /// human has typed one.
    public mutating func choose(script: JobScript) {
        command = script.command
        if nameSuggested {
            name = JobDraft.suggestedName(folder: folder, script: script.file)
        }
    }

    /// The footer's words for the first thing the sheet still needs, or nil.
    public var missing: String? {
        if profile == nil, folder.isEmpty {
            return "Choose the profile whose secrets the script needs"
        }
        if folder.isEmpty {
            return "Choose the folder the job runs in"
        }
        if argv.isEmpty {
            return "Choose what the AI tool may run"
        }
        if editing != nil, changes.isEmpty {
            return "Nothing changed yet"
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
        slug((folder as NSString).lastPathComponent)
    }

    /// A job name from a folder and a script in it: "notion" and
    /// "list_guest_users.py" → "notion-list-guest-users". The folder is
    /// dropped when the script already starts with it.
    public static func suggestedName(folder: String, script: String) -> String {
        let base = slug((folder as NSString).lastPathComponent)
        let stem = slug((script as NSString).deletingPathExtension)
        if base.isEmpty || stem == base || stem.hasPrefix(base + "-") {
            return String(stem.prefix(40))
        }
        return String((base + "-" + stem).prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func slug(_ text: String) -> String {
        let mapped = text.lowercased().map { ($0.isASCII && ($0.isLetter || $0.isNumber)) ? $0 : "-" }
        var out = ""
        for ch in mapped where !(ch == "-" && out.hasSuffix("-")) {
            out.append(ch)
        }
        return String(out.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(40))
    }

    /// The sentence the Touch ID will say, as parts: a blank stays grey
    /// until chosen, and nothing is claimed that has not been checked.
    /// `program` and `secrets` are what the service resolved, when it has.
    public func sentence(program: String?, secrets: Int?) -> [GrantDraft.Part] {
        var parts: [GrantDraft.Part] = [.text("Let AI tools run ")]
        // The script an interpreter runs (`python a.py`), else the program.
        let guess = argv.count > 1 && !argv[1].hasPrefix("-") ? argv[1] : argv.first
        let script = argv.isEmpty ? nil : (program ?? guess.map { ($0 as NSString).lastPathComponent })
        parts.append(script.map { .value($0) } ?? .blank("a script"))
        if !folder.isEmpty {
            parts.append(.text(" in "))
            parts.append(.value((folder as NSString).lastPathComponent))
        }
        parts.append(.text(" with "))
        if let secrets {
            parts.append(.value(secrets == 1 ? "1 secret" : "\(secrets) secrets"))
        } else if let profile {
            parts.append(.value(profile + "'s secrets"))
        } else {
            parts.append(.blank("a profile's secrets"))
        }
        parts.append(.text(". They see what it prints, never the values."))
        return parts
    }

    public func spec(pathEnv: String, home: String) -> JobSpec {
        JobSpec(
            dir: folder, argv: argv,
            profile: profile.map { GrantProfile(name: $0, root: global ? nil : profileRoot ?? folder) },
            ask: ask.rawValue,
            shown: shown.isEmpty ? nil : shown.sorted(),
            outputs: output.isEmpty ? nil : [output],
            pathEnv: pathEnv, home: home,
            description: editing?.description,
            replace: editing == nil ? nil : true
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
