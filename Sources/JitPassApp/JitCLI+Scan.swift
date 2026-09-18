// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

extension JitCLI {
    /// Where every spawned jit runs. An app opened from Finder sits in `/`,
    /// and `jit doctor` looks for MCP configs under its working directory:
    /// from `/` that is a walk of the whole disk, which also meets every
    /// file in the home folder twice, once under `/Users` and once under
    /// `/System/Volumes/Data/Users`. Home is where a terminal starts.
    static var workingDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// A scan someone is watching: `onLines` hears how many records have
    /// arrived so far (findings, then the summary), so the wait shows work
    /// that is really happening, and `run` lets the caller stop it.
    static func scan(
        path: String?, excludes: [String], run: ScanRun, onLines: @escaping @Sendable (Int) -> Void
    ) throws -> ScanReport {
        guard let jit = executable else {
            throw CLIError.notInstalled
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jit)
        process.arguments = ["scan", "--format", "ndjson"] + excludes.flatMap { ["--exclude", $0] } + (path.map { [$0] } ?? [])
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        run.started(process)
        var data = Data()
        var lines = 0
        while true {
            let chunk = out.fileHandleForReading.availableData
            if chunk.isEmpty {
                break
            }
            data.append(chunk)
            lines += chunk.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
            onLines(lines)
        }
        process.waitUntilExit()
        if run.cancelled {
            throw CLIError.failed("cancelled")
        }
        return try ScanReport.parse(data)
    }

    /// The handle on a running scan, so a Cancel button can end it.
    final class ScanRun: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var stopped = false

        var cancelled: Bool {
            lock.withLock { stopped }
        }

        func started(_ process: Process) {
            lock.withLock {
                self.process = process
                if stopped {
                    process.terminate()
                }
            }
        }

        func cancel() {
            lock.withLock {
                stopped = true
                process?.terminate()
            }
        }
    }
}
