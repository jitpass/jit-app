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
        if reported == "(the program itself)" {
            file = job.exe
            label = job.exe.map { ($0 as NSString).lastPathComponent + " (the program itself)" } ?? reported
        } else if reported.hasPrefix("outside:") {
            file = String(reported.dropFirst("outside:".count))
            label = file ?? reported
        } else {
            let relative = reported.hasSuffix(" (its target)") ? String(reported.dropLast(" (its target)".count)) : reported
            file = (job.dir as NSString).appendingPathComponent(relative)
        }
        if change.kind == "removed" {
            file = nil
        }
        return Item(reported: reported, kind: change.kind, file: file, label: label)
    }

    /// The same job, approved again: its folder, command, profile, shown
    /// values, outputs and ask mode as they are, replacing the stopped one.
    /// The PATH is the approving environment's now, as `jit job allow
    /// --replace` would capture it.
    public func reapproval(pathEnv: String, home: String) -> JobSpec {
        JobSpec(
            dir: job.dir, argv: job.argv,
            profile: job.profile.map { GrantProfile(name: $0, root: job.dir) },
            ask: job.ask,
            shown: job.secrets?.filter(\.isShown).map(\.name),
            outputs: job.outputs,
            pathEnv: pathEnv, home: home,
            description: job.description,
            replace: true
        )
    }
}
