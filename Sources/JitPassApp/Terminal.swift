// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit

/// Hands a jit command to the user's own terminal. The app never runs jit
/// with output it would have to render itself; scan and audit stay terminal
/// surfaces with their own house style.
///
/// macOS has no "default terminal" setting, so the choice is layered:
///
/// 1. `defaults write com.jitpass.app TerminalApp iTerm2` names one outright.
/// 2. A running terminal that can execute a `.command` file, preferring a
///    third-party one over Terminal.app: the app the user keeps open is the
///    one they work in, and Terminal.app is often open only incidentally.
/// 3. The LaunchServices handler for `.command` files (Terminal unless the
///    user changed it).
///
/// The command travels as a temporary `.command` script the terminal opens
/// and runs, which is the one launch mechanism every terminal supports
/// without an AppleScript dictionary or an Apple Events entitlement.
enum Terminal {
    static let preferenceKey = "TerminalApp"

    /// Terminals known to open and run a `.command` file, in the order to
    /// prefer them when several are running.
    static let scriptRunners = ["iTerm2", "Warp", "Terminal"]

    /// What Settings offers. "" is automatic: the rules above.
    static let choices = ["", "iTerm2", "Terminal", "Warp", "Ghostty", "kitty", "Alacritty", "WezTerm"]

    /// Single-quotes a path for the script, escaping embedded quotes, so a
    /// folder name with spaces or quotes survives the shell.
    static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func run(_ command: String) {
        guard let script = writeScript(command) else {
            return
        }
        if let app = chosenApp() {
            NSWorkspace.shared.open([script], withApplicationAt: app, configuration: .init()) { _, _ in }
        } else {
            NSWorkspace.shared.open(script)
        }
    }

    /// The app to open the script with, or nil to let LaunchServices decide.
    static func chosenApp() -> URL? {
        let running = NSWorkspace.shared.runningApplications
        if let name = UserDefaults.standard.string(forKey: preferenceKey), !name.isEmpty {
            if let url = running.first(where: { $0.localizedName == name })?.bundleURL ?? applicationURL(named: name) {
                return url
            }
        }
        for name in scriptRunners {
            if let app = running.first(where: { $0.localizedName == name }), let url = app.bundleURL {
                return url
            }
        }
        return nil
    }

    private static func applicationURL(named name: String) -> URL? {
        let candidates = ["/Applications/\(name).app", "/System/Applications/Utilities/\(name).app"]
        return candidates.map { URL(fileURLWithPath: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A self-deleting script in a private temp directory. `$0` is quoted so
    /// a path with spaces still deletes; the command itself is written
    /// verbatim, and only fixed strings from this app ever reach here.
    private static func writeScript(_ command: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jitpass", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("jit-\(UUID().uuidString.prefix(8)).command")
        let body = "#!/bin/zsh\n\(command)\nrm -f -- \"$0\"\n"
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            return nil
        }
        return url
    }
}
