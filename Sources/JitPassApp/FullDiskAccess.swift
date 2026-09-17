// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit

/// A whole-Mac scan reads Desktop, Documents, Downloads and any network
/// volume, and macOS asks about each one the first time, naming this app.
/// One Full Disk Access grant replaces all of those prompts. It cannot be
/// requested from code, only given in System Settings, so the scan window
/// says whether it is there and opens the right pane.
enum FullDiskAccess {
    /// A file macOS lets a process read only with Full Disk Access. The
    /// TCC database is the canonical probe: it exists on every Mac and is
    /// unreadable without the grant.
    private static let probe = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path

    static func granted() -> Bool {
        guard let handle = FileHandle(forReadingAtPath: probe) else {
            return false
        }
        try? handle.close()
        return true
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
