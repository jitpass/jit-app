// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit

/// Hands a jit command to the user's own terminal.
///
/// This is for a command that genuinely needs a human at a prompt: a tool
/// log-in opens a browser, shows a code and waits. The app cannot run that
/// silently and must not pretend to, so the button says what it does
/// ("Log In in Terminal") and the question keeps its command line, because
/// the app is not the one running it.
///
/// It is NOT for a job the app could do itself. A footer that re-runs
/// `jit doctor`, a menu offering `jit vault orphans`, an unmount asking
/// its own y/N per mount: each of those is a window the app has or should
/// build. Scan and audit both have their own window now; the one terminal
/// route left there is `AuditView.capNote`, kept on purpose until the
/// engine can page an audit log. The rule is the design system's Windows
/// section, "When the terminal is still right".
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

    /// A self-deleting script in a private temp directory. It deletes
    /// itself first (the shell already holds the file open), clears the
    /// path iTerm2 typed to launch it, shows the command the way a prompt
    /// would, runs it, then hands the window to the user's shell: iTerm2
    /// appends `; exit` to a `.command` launch and closes the session the
    /// moment the script returns, so without that last line a short
    /// listing flashed and was gone. The command itself is written
    /// verbatim; only fixed strings from this app ever reach here.
    private static func writeScript(_ command: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jitpass", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("jit-\(UUID().uuidString.prefix(8)).command")
        let shown = command.split(separator: "\n").map { "$ " + $0 }.joined(separator: "\n")
        let body = """
        #!/bin/zsh
        rm -f -- "$0"
        printf '\\e[H\\e[2J'
        print -r -- \(quoted(shown))
        \(command)
        exec "${SHELL:-/bin/zsh}"

        """
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            return nil
        }
        return url
    }
}
