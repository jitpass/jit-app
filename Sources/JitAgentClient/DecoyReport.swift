// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The Decoys window's facts, worked out once from the service's mount
/// list, the vault listing, the serve events and the last scan: which
/// files serve decoys, who read them and what they got, which still hold
/// plaintext, and which name a secret the vault does not have. Every
/// number here is a number on a card.
public struct DecoyReport: Equatable, Sendable {
    /// One protected file.
    public struct File: Equatable, Sendable, Identifiable {
        public var path: String
        /// Vault entries whose origin is this file.
        public var secrets: Int
        public var decoyReads: Int
        public var realReads: Int
        public var lastRealRead: Date?
        /// The last time anything opened it, from the service.
        public var lastRead: Date?
        /// A variable the file names that the vault does not hold, seen
        /// when a run asked for it and got nothing.
        public var missing: String?
        public var missingAt: Date?

        public var id: String {
            path
        }
    }

    /// One moment something read a protected file: every event at that
    /// second with the same reason, so three files opened at once are
    /// one row.
    public struct Read: Equatable, Sendable, Identifiable {
        public var at: Date
        public var files: [String]
        public var reads: Int
        public var reader: String?
        public var real: Bool
        /// The engine's reason, in the reader's words.
        public var why: String

        public var id: String {
            "\(Int(at.timeIntervalSince1970)):\(why):\(real)"
        }
    }

    public var files: [File]
    public var reads: [Read]

    public var protected: [File] {
        files.filter { $0.missing == nil }
    }

    public var broken: [File] {
        files.filter { $0.missing != nil }
    }

    public var decoyReads: Int {
        reads.filter { !$0.real }.reduce(0) { $0 + $1.reads }
    }

    public var realReads: Int {
        reads.filter(\.real).reduce(0) { $0 + $1.reads }
    }

    /// Every decoy read happened because the vault was locked: jit working,
    /// and the one sentence that says so.
    public var allWhileLocked: Bool {
        let decoys = reads.filter { !$0.real }
        return !decoys.isEmpty && decoys.allSatisfy { $0.why == Self.lockedWhy }
    }

    public var secrets: Int {
        files.reduce(0) { $0 + $1.secrets }
    }

    public static let lockedWhy = "the vault was locked"

    /// `home` is the user's home directory: serve events name files with
    /// "~", the registry with the full path.
    public static func make(mounts: [CLIMount], secrets: [VaultSecret], events: [SessionEvent], home: String) -> DecoyReport {
        let serves = events.filter { $0.kind == "serve" }
        var files = mounts.map { mount -> File in
            let path = mount.path
            let short = abbreviate(path, home: home)
            // The vault records an origin with "~", the service lists the
            // mount in full; a secret is this file's in either spelling.
            let origins = secrets.filter { $0.origin == path || $0.origin == short }.count
            var file = File(path: path, secrets: origins, decoyReads: 0, realReads: 0, lastRead: mount.lastServe?.date)
            for event in serves where (event.labels ?? []).contains(short) {
                let n = event.count ?? 1
                if event.op == "real" {
                    file.realReads += n
                    if file.lastRealRead.map({ event.date > $0 }) ?? true {
                        file.lastRealRead = event.date
                    }
                } else if event.undelivered != true {
                    file.decoyReads += n
                }
                if let name = missingVariable(event.cause), file.missingAt.map({ event.date > $0 }) ?? true {
                    file.missing = name
                    file.missingAt = event.date
                }
            }
            return file
        }
        files.sort { ($0.missing == nil ? 1 : 0, $0.path) < ($1.missing == nil ? 1 : 0, $1.path) }

        var reads: [Read] = []
        for event in serves.sorted(by: { $0.unixTime > $1.unixTime }) {
            let real = event.op == "real"
            let why = reason(event)
            let reader = event.by.flatMap { AuditReport.program($0) }
            let sameMoment = { (read: Read) in
                Int(read.at.timeIntervalSince1970) == Int(event.unixTime) && read.why == why && read.real == real && read.reader == reader
            }
            if let index = reads.firstIndex(where: sameMoment) {
                reads[index].files += (event.labels ?? []).filter { !reads[index].files.contains($0) }
                reads[index].reads += event.undelivered == true ? 0 : (event.count ?? 1)
            } else {
                reads.append(Read(
                    at: event.date,
                    files: event.labels ?? [],
                    reads: event.undelivered == true ? 0 : (event.count ?? 1),
                    reader: reader,
                    real: real,
                    why: why
                ))
            }
        }
        return DecoyReport(files: files, reads: reads)
    }

    /// The engine's cause, in the reader's words. Unknown causes keep
    /// jit's own sentence.
    static func reason(_ event: SessionEvent) -> String {
        if event.op == "real" {
            return "the real values, through jit"
        }
        guard let cause = event.cause else {
            return "the decoy was served"
        }
        if cause.contains("session is locked") {
            return lockedWhy
        }
        if let name = missingVariable(cause) {
            return "a run asked for \(name) · not in the vault · nothing was served"
        }
        return cause
    }

    /// "resolving HIBOB_BASE_URL (hibob/HIBOB_BASE_URL): secret not found"
    /// names the variable a protected file lists and the vault lacks.
    static func missingVariable(_ cause: String?) -> String? {
        guard let cause, cause.contains("secret not found"),
              let range = cause.range(of: #"resolving ([A-Za-z_][A-Za-z0-9_]*) \("#, options: .regularExpression)
        else {
            return nil
        }
        let match = cause[range]
        return String(match.dropFirst("resolving ".count).dropLast(2))
    }

    static func abbreviate(_ path: String, home: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
