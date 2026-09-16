// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Runs the installed `jit` for the one read-only report the panel needs.
/// Resolved from PATH the way a shell would, with the Homebrew prefix as the
/// fallback a GUI app's PATH usually lacks.
enum JitCLI {
    static let candidates = ["/opt/homebrew/bin/jit", "/usr/local/bin/jit"]

    static var executable: String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Every `jit status` run is itself a line in `jit audit`, so the panel
    /// reads it at most once per statusCacheTTL rather than on every open.
    private static var cachedStatus: (at: Date, value: CLIStatus?)?
    static let statusCacheTTL: TimeInterval = 30

    static func status() -> CLIStatus? {
        if let cached = cachedStatus, Date().timeIntervalSince(cached.at) < statusCacheTTL {
            return cached.value
        }
        let value = run(["status", "--format", "json"]).flatMap { try? JSONDecoder().decode(CLIStatus.self, from: $0) }
        cachedStatus = (Date(), value)
        return value
    }

    static func audit(_ filter: AuditFilter) -> AuditReport? {
        guard let data = run(filter.arguments) else {
            return nil
        }
        return try? JSONDecoder().decode(AuditReport.self, from: data)
    }

    /// A whole-machine scan. Read-only in every mode and prompt-free, so it
    /// is safe to run from a GUI; it takes seconds, so callers run it off
    /// the main thread.
    static func scan(path: String? = nil) throws -> ScanReport {
        guard let data = run(["scan", "--format", "ndjson"] + (path.map { [$0] } ?? [])) else {
            throw ScanReportError.noSummary
        }
        return try ScanReport.parse(data)
    }

    private static func run(_ arguments: [String]) -> Data? {
        guard let jit = executable else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jit)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}
