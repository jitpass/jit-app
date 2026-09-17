// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit

/// Gatekeeper runs an app opened straight from its download (still in
/// ~/Downloads, quarantined, never moved) from a randomised read-only copy
/// under /private/var/folders/…/AppTranslocation/. Nothing in the app
/// breaks there, but everything the app points other software at does:
/// the bundled `jit` the PATH symlink resolves to, the service the launchd
/// job starts, the path Full Disk Access is granted to. All of them would
/// name a copy that is gone on the next launch. Says so once, before
/// anything is set up, and lets the user choose.
enum Translocation {
    static func isActive(bundlePath: String = Bundle.main.bundlePath) -> Bool {
        bundlePath.contains("/AppTranslocation/")
    }

    /// True to go on, false to quit.
    @MainActor
    static func warnIfNeeded() -> Bool {
        guard isActive() else {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "Move JitPass to Applications first"
        alert.informativeText = "macOS is running this copy from a temporary location because it was opened "
            + "straight from the download. The jit command it bundles and the service it starts need a fixed path.\n\n"
            + "Quit, drag JitPass.app into your Applications folder, and open it from there."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Continue Anyway")
        return alert.runModal() != .alertFirstButtonReturn
    }
}
