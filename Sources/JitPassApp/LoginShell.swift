// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The PATH the user's terminal has. A GUI app inherits launchd's, which
/// lacks Homebrew, ~/.local/bin and whatever nvm, rbenv, cargo or go add
/// in the shell's rc files, so the tool listing called those tools "not
/// installed" on a Mac that runs them daily. Asking the login shell once
/// answers with the same PATH a terminal would have.
enum LoginShell {
    /// Read once, on first use; `warm()` does that off the main thread at
    /// startup so no window waits on it. Nil when the shell did not answer
    /// in time, in which case the fixed list below stands in.
    static let path: String? = probe()

    static func warm() {
        Task.detached(priority: .utility) { _ = path }
    }

    /// The fallback and the floor: the shim dir first, as the rc line puts
    /// it, so doctor's "shim dir on PATH" check describes the user's shell;
    /// then the login shell's PATH (or the prefixes a Mac usually has),
    /// then the app's own so nothing it could reach before is lost.
    static func mergedPath(login: String?, app: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let shims = home.appendingPathComponent(".jit/shims").path
        let usual = ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path]
        let loginDirs = login?.split(separator: ":").map(String.init) ?? usual
        let appDirs = app.split(separator: ":").map(String.init)
        var seen = Set<String>()
        var out: [String] = []
        for dir in [shims] + loginDirs + appDirs where !dir.isEmpty && seen.insert(dir).inserted {
            out.append(dir)
        }
        return out.joined(separator: ":")
    }

    /// Runs the user's shell as a login shell and asks for PATH. Interactive
    /// too for zsh and bash, because ~/.zshrc is where most PATH lines
    /// live; stdin is closed so nothing can wait on a prompt, and three
    /// seconds is the most a slow rc file gets before the fallback wins.
    static func probe() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else {
            return nil
        }
        let name = (shell as NSString).lastPathComponent
        let arguments: [String] = switch name {
        case "fish": ["-lc", "string join : $PATH"]
        case "zsh", "bash": ["-lic", "printf '%s\\n' \"$PATH\""]
        default: ["-lc", "printf '%s\\n' \"$PATH\""]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let out = Pipe()
        process.standardOutput = out
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: deadline)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        // The last line: an rc file that prints a greeting puts it first.
        let line = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { $0.contains("/") }
        return line?.isEmpty == false ? line : nil
    }
}
