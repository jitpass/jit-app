// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A running process the user might grant to, described the way a person
/// tells two of them apart: what it is, the folder it is working in, the
/// terminal or editor it runs under, and how long it has been running.
/// Listed through `ps` and `lsof`, the same view of the process table the
/// user has; the agent verifies the pid and its fork time itself.
struct RunningProcess: Identifiable, Hashable {
    let pid: Int32
    let name: String
    /// The terminal or editor at the top of its ancestry ("iTerm2",
    /// "Code"), or the direct parent when none is recognised.
    let under: String
    /// Its working directory, "~"-shortened, or "" when unreadable.
    let folder: String
    /// `ps` elapsed time, "12:34" or "1-02:03:04".
    let elapsed: String

    var id: Int32 {
        pid
    }

    /// "1-02:03:04" -> "1d", "02:03:04" -> "2h", "12:34" -> "12m", "45" -> "now".
    static func age(_ elapsed: String) -> String {
        let dayParts = elapsed.split(separator: "-")
        if dayParts.count == 2, let days = Int(dayParts[0]) {
            return "\(days)d"
        }
        let fields = elapsed.split(separator: ":").compactMap { Int($0) }
        switch fields.count {
        case 3: return "\(fields[0])h"
        case 2: return fields[0] == 0 ? "now" : "\(fields[0])m"
        default: return "now"
        }
    }
}

enum RunningProcesses {
    /// Names the sheet offers first: the agents jit wraps, plus the usual
    /// long-running tools. Everything else is reachable through "show all".
    static let likely: Set<String> = [
        "claude", "codex", "gemini", "cursor-agent", "copilot", "cline", "opencode", "kiro-cli",
        "node", "python", "python3", "make", "go", "terraform", "kubectl", "docker"
    ]

    /// The apps a process is said to run "under": the top of a chain that a
    /// human would name. Anything else is walked through.
    static let sessionApps: Set<String> = [
        "iTerm2", "Terminal", "Warp", "Ghostty", "kitty", "alacritty", "wezterm-gui",
        "tmux", "Code", "Cursor", "Windsurf", "Zed", "Xcode", "JitPass"
    ]

    static func list(all: Bool) -> [RunningProcess] {
        let rows = psRows()
        let byPID = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let chosen = rows
            .filter { $0.pid != ProcessInfo.processInfo.processIdentifier }
            .filter { all || likely.contains($0.name) }
        let folders = workingDirectories(of: chosen.map(\.pid))
        return chosen
            .map { row in
                RunningProcess(
                    pid: row.pid,
                    name: row.name,
                    under: sessionApp(of: row, in: byPID),
                    folder: folders[row.pid].map(Format.home) ?? "",
                    elapsed: row.elapsed
                )
            }
            .sorted { $0.name == $1.name ? $0.pid > $1.pid : $0.name < $1.name }
    }

    // MARK: - ps

    /// One `ps` line: pid, parent pid, elapsed time, and the command's last
    /// path component.
    private struct Row {
        let pid: Int32
        let ppid: Int32
        let elapsed: String
        let name: String

        init?(_ line: Substring) {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else {
                return nil
            }
            self.pid = pid
            self.ppid = ppid
            elapsed = String(parts[2])
            name = String(parts[3].split(separator: "/").last ?? parts[3])
        }
    }

    private static func psRows() -> [Row] {
        guard let text = capture("/bin/ps", ["-axo", "pid=,ppid=,etime=,comm="]) else {
            return []
        }
        return text.split(separator: "\n").compactMap(Row.init)
    }

    /// Walks the parent chain until a recognised app, else the direct parent.
    private static func sessionApp(of row: Row, in byPID: [Int32: Row]) -> String {
        var cur = byPID[row.ppid]
        var hops = 0
        while let parent = cur, hops < 16 {
            if sessionApps.contains(parent.name) {
                return parent.name
            }
            cur = byPID[parent.ppid]
            hops += 1
        }
        return byPID[row.ppid]?.name ?? ""
    }

    // MARK: - lsof

    /// Working directories for the given pids in ONE lsof call. Output is
    /// field-per-line: "p<pid>" starts a process, "n<path>" is its cwd.
    private static func workingDirectories(of pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty,
              let text = capture("/usr/sbin/lsof", ["-a", "-d", "cwd", "-F", "pn", "-p", pids.map(String.init).joined(separator: ",")])
        else {
            return [:]
        }
        var out: [Int32: String] = [:]
        var current: Int32?
        for line in text.split(separator: "\n") {
            switch line.first {
            case "p": current = Int32(line.dropFirst())
            case "n": if let pid = current {
                    out[pid] = String(line.dropFirst())
                }
            default: continue
            }
        }
        return out
    }

    private static func capture(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
