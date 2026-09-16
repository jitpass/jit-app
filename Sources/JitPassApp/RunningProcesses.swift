// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A running process the user might grant to: an AI agent, a build, a
/// script. Listed through `ps` because that is the same view of the process
/// table the user has; the agent verifies the pid and its fork time itself.
struct RunningProcess: Identifiable, Hashable {
    let pid: Int32
    let name: String
    let parent: String

    var id: Int32 {
        pid
    }

    var label: String {
        parent.isEmpty ? "\(name) · pid \(pid)" : "\(name) · pid \(pid) · under \(parent)"
    }
}

enum RunningProcesses {
    /// Names the sheet offers first: the agents jit wraps, plus the usual
    /// long-running tools. Everything else is reachable through "show all".
    static let likely: Set<String> = [
        "claude", "codex", "gemini", "cursor-agent", "copilot", "cline", "opencode", "kiro-cli",
        "node", "python", "python3", "make", "go", "terraform", "kubectl", "docker"
    ]

    static func list(all: Bool) -> [RunningProcess] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid=,comm="]
        let out = Pipe()
        ps.standardOutput = out
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else {
            return []
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let rows = text.split(separator: "\n").compactMap(Row.init)
        let names = Dictionary(rows.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })
        return rows
            .filter { $0.pid != ProcessInfo.processInfo.processIdentifier }
            .filter { all || likely.contains($0.name) }
            .map { RunningProcess(pid: $0.pid, name: $0.name, parent: names[$0.ppid] ?? "") }
            .sorted { $0.name == $1.name ? $0.pid > $1.pid : $0.name < $1.name }
    }

    /// One `ps` line: pid, parent pid, and the command's last path component.
    private struct Row {
        let pid: Int32
        let ppid: Int32
        let name: String

        init?(_ line: Substring) {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else {
                return nil
            }
            self.pid = pid
            self.ppid = ppid
            name = String(parts[2].split(separator: "/").last ?? parts[2])
        }
    }
}
