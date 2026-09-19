// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

extension JitCLI {
    /// `jit vault rm --dry-run --format json <paths>`: what a delete would
    /// remove and who still uses it. Prompt-free and writes nothing. A jit
    /// before 1.9 has no --dry-run and exits 1 with "unknown flag"; that,
    /// and any output that is not a plan, is a failure, and the caller
    /// deletes nothing.
    static func vaultRmPlan(_ paths: [String]) -> Result<VaultRmPlan, Error> {
        dryRun(VaultRmPlan.arguments(for: paths), parse: VaultRmPlan.parse)
    }

    /// A `--dry-run --format json` plan: jit's own answer to "what would
    /// this do", prompt-free. A nonzero exit (an older jit's "unknown
    /// flag") or output that is not a plan is a failure, and the caller
    /// runs nothing.
    static func dryRun<Plan>(_ arguments: [String], parse: @escaping (Data) throws -> Plan) -> Result<Plan, Error> {
        capture(arguments).flatMap { captured in
            guard captured.status == 0 else {
                let said = captured.stderr.isEmpty ? String(data: captured.stdout, encoding: .utf8) ?? "" : captured.stderr
                let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(CLIError.failed(text.isEmpty ? "jit exited \(captured.status)" : text))
            }
            return Result { try parse(captured.stdout) }
                .mapError { _ in CLIError.failed("jit printed no plan (\(executable ?? "jit") is too old, or not jit)") }
        }
    }

    /// `jit profile attach --dry-run --format json <config>` (jit 2.0+).
    static func profileAttachPlan(_ config: String) -> Result<ProfileAttachPlan, Error> {
        dryRun(ProfileAttachPlan.arguments(for: config), parse: ProfileAttachPlan.parse)
    }

    /// `jit profile rm --dry-run --format json <name>` (jit 2.0+).
    static func profileRmPlan(_ name: String) -> Result<ProfileRmPlan, Error> {
        dryRun(ProfileRmPlan.arguments(for: name), parse: ProfileRmPlan.parse)
    }

    struct Captured {
        var status: Int32
        var stdout: Data
        var stderr: String
    }

    /// Runs jit with stdout and stderr apart, for machine output that a
    /// warning on stderr must not corrupt. No stdin: nothing here asks.
    static func capture(_ arguments: [String]) -> Result<Captured, Error> {
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
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let complaint = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return .success(Captured(status: process.terminationStatus, stdout: data, stderr: String(data: complaint, encoding: .utf8) ?? ""))
    }
}
