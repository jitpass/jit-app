// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit

/// Hands a jit command to the user's terminal. The app never runs jit with
/// output it would have to render itself; scan and audit stay terminal
/// surfaces with their own house style.
enum Terminal {
    static func run(_ command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }
}
