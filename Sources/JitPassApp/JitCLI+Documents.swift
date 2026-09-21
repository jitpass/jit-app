// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// The commands that answer with one JSON document the windows read by
/// its fields: a Protect's migrate, and Redact. stderr is kept apart so a
/// progress line cannot land inside the document.
extension JitCLI {
    /// `jit migrate <paths> --yes --format json`: the run as one document
    /// the banner reads by its fields (MigrateReport). stderr is kept
    /// apart so a progress line cannot land inside the document. A run
    /// that failed but still wrote its document returns it — the partial
    /// result is real, and its errors are in the report; only a run that
    /// wrote no document is a failure here.
    static func migrate(_ paths: [String]) -> Result<MigrateReport, Error> {
        document(["migrate"] + paths + ["--yes", "--format", "json"], parse: MigrateReport.parse)
    }

    /// `jit migrate redact <files> --line N --yes --format json`: tokens the
    /// scan found by format in agent caches become markers. No vault, no
    /// backup, no prompt (jit's D12). Empty `files` is every cache.
    static func redact(files: [String], lines: [Int]) -> Result<RedactReport, Error> {
        document(
            ["migrate", "redact"] + files + lines.flatMap { ["--line", String($0)] } + ["--yes", "--format", "json"],
            parse: RedactReport.parse
        )
    }

    /// Runs a command that writes one JSON document, stderr kept apart so a
    /// progress line cannot land inside it. A run that failed but still
    /// wrote its document returns it — the partial result is real and its
    /// errors are in the report; only a run that wrote none is a failure.
    static func document<Report>(_ arguments: [String], parse: (String) throws -> Report) -> Result<Report, Error> {
        guard let jit = executable else {
            return .failure(CLIError.notInstalled)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jit)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failure(error)
        }
        spawned.insert(process.processIdentifier)
        defer { spawned.remove(process.processIdentifier) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if let report = try? parse(String(data: data, encoding: .utf8) ?? "") {
            return .success(report)
        }
        let stderr = (String(data: errData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return .failure(CLIError.failed(stderr.split(separator: "\n").last.map(String.init) ?? "jit wrote no report"))
    }
}
