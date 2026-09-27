// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Reviewing a stopped job (the Jobs mockup, frame F): each change named as
/// the human would find the file, and the spec that approves the same job
/// again. jit keeps fingerprints, not copies, so the old text is not here;
/// the review offers the file itself, and git's diff where git has one.
public struct JobReview: Sendable, Equatable {
    public struct Item: Sendable, Equatable, Identifiable {
        /// As the service reported it: a path in the folder, "outside:/abs",
        /// "x (its target)", or "(the program itself)".
        public var reported: String
        public var kind: String
        /// The file to open, absolute; nil when there is none (removed).
        public var file: String?
        /// What to show: the path as the human knows it.
        public var label: String
        /// The row's chip: one short word, since a chip does not wrap.
        public var badge: String = ""
        /// Said in place of "changed since approval" when the kind needs
        /// more than that; nil for a plain file change.
        public var note: String?

        public var id: String {
            reported
        }
    }

    public var job: JobStatus
    public var items: [Item]

    public init(job: JobStatus) {
        self.job = job
        items = (job.changes ?? []).map { JobReview.item($0, job: job) }
    }

    static func item(_ change: JobChange, job: JobStatus) -> Item {
        let reported = change.path
        var file: String?
        var label = reported
        var note: String?
        if reported == JobChange.libsPath {
            // Not a file: everything the program loads from outside the
            // folder, which an approval by an older jit never fingerprinted.
            label = "What the program loads from outside the folder"
            note = "Approved by an older jit, which didn't fingerprint these files · approving again adds them"
        } else if reported == "(the program itself)" {
            file = job.exe
            label = job.exe.map { ($0 as NSString).lastPathComponent + " (the program itself)" } ?? reported
        } else if reported.hasPrefix("outside:") {
            file = String(reported.dropFirst("outside:".count))
            label = file ?? reported
        } else if reported.hasPrefix("/") {
            // A library outside the folder is reported by its absolute path.
            file = reported
        } else {
            let relative = reported.hasSuffix(" (its target)") ? String(reported.dropLast(" (its target)".count)) : reported
            file = (job.dir as NSString).appendingPathComponent(relative)
        }
        if change.kind == "removed" {
            file = nil
        }
        switch change.kind {
        case JobChange.folderChanged: note = "A file in this folder changed · jit can't say which"
        case JobChange.folderRewritten: note = "A file in this folder was written to, its content matching · jit can't say which"
        default: break
        }
        return Item(reported: reported, kind: change.kind, file: file, label: label, badge: change.badge, note: note)
    }

    /// The same job, approved again: its folder, command, profile, shown
    /// values, outputs and ask mode as they are, replacing the stopped one.
    /// The PATH is the approving environment's now, as `jit job allow
    /// --replace` would capture it.
    public func reapproval(pathEnv: String, home: String) -> JobSpec {
        JobSpec(
            dir: job.dir, argv: job.argv,
            profile: job.profile.map { GrantProfile(name: $0, root: job.profileGlobal == true ? nil : job.profileRoot ?? job.dir) },
            ask: job.ask,
            shown: job.secrets?.filter(\.isShown).map(\.name),
            outputs: job.outputs,
            pathEnv: pathEnv, home: home,
            description: job.description,
            replace: true
        )
    }
}
