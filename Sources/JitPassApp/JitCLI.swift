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

    /// Runs a settings command and returns its last line, or the error. Both
    /// restart the service, and `consent off` puts the CLI's own Touch ID
    /// prompt on screen, so the call may take a while; callers run it off
    /// the main thread.
    static func apply(_ arguments: [String]) -> Result<String, Error> {
        guard let jit = executable else {
            return .failure(CLIError.notInstalled)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jit)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        do {
            try process.run()
        } catch {
            return .failure(error)
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = text.split(separator: "\n").last.map(String.init) ?? ""
        return process.terminationStatus == 0 ? .success(last) : .failure(CLIError.failed(last))
    }

    enum CLIError: Error {
        case notInstalled
        case failed(String)
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
