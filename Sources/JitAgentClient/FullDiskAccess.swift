// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Whether macOS has given this app Full Disk Access. A whole-Mac scan reads
/// Desktop, Documents, Downloads and any network volume, and macOS asks about
/// each one the first time, naming this app. One grant replaces all of those
/// prompts. It cannot be requested from code, only given in System Settings,
/// so the app says whether it is there and opens the right pane.
///
/// Lives here rather than in the app target because the answer is a file
/// probe, not a view: it is the part that can be wrong, so it is the part
/// that gets tests. `openSettings` stays in the app, with AppKit.
public enum FullDiskAccess {
    /// The TCC databases, most-certain first. Each is readable only with the
    /// grant, and each may be absent: the per-user database is gone on macOS
    /// 27 (26A428 has no `~/Library/Application Support/com.apple.TCC` at
    /// all), which is what made a single hardcoded path report "needs Full
    /// Disk Access" to a user who had already granted it. A probe that
    /// cannot tell "denied" from "not on this macOS" answers the wrong
    /// question.
    public static var probes: [String] {
        [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
        ]
    }

    public static func granted() -> Bool {
        granted(probing: probes)
    }

    /// Opened means the grant is there. `EPERM`/`EACCES` means it is not, and
    /// is an answer: stop, rather than letting a later candidate overrule it.
    /// `ENOENT` means this macOS does not keep that file, which is no answer
    /// at all, so the next candidate gets asked. Out of candidates, say no:
    /// the cost is an offer to grant something already granted, against a
    /// scan that walks into a prompt per folder.
    public static func granted(probing paths: [String]) -> Bool {
        for path in paths {
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return true
            }
            let failure = errno
            if failure == ENOENT || failure == ENOTDIR {
                continue
            }
            return false
        }
        return false
    }
}
