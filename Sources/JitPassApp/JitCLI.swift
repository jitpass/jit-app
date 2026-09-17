// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Runs `jit` for the read-only reports the panel needs. The copy inside
/// this bundle comes first: it is the exact release the app was built and
/// tested against, and the one the `jitpass` cask puts on PATH. A dev build
/// run from `.build/` has no bundled copy and falls back to the Homebrew
/// prefixes a GUI app's PATH usually lacks.
enum JitCLI {
    static var candidates: [String] {
        let bundled = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("jit").path
        return [bundled].compactMap { $0 } + ["/opt/homebrew/bin/jit", "/usr/local/bin/jit"]
    }

    static var executable: String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Every `jit status` run is itself a line in `jit audit`, so the panel
    /// reads it at most once per statusCacheTTL rather than on every open.
    private static var cachedStatus: (at: Date, value: CLIStatus?)?
    static let statusCacheTTL: TimeInterval = 30

    /// Drops the cached status, for after something changed the vault.
    static func forgetStatus() {
        cachedStatus = nil
    }

    static func status() -> CLIStatus? {
        if let cached = cachedStatus, Date().timeIntervalSince(cached.at) < statusCacheTTL {
            return cached.value
        }
        let value = run(["status", "--format", "json"]).flatMap { try? JSONDecoder().decode(CLIStatus.self, from: $0) }
        cachedStatus = (Date(), value)
        return value
    }

    /// Prompt-free: doctor checks envelopes without decrypting anything.
    static func doctor() -> DoctorReport? {
        guard let data = run(["doctor", "--format", "json", "--orphans"]) else {
            return nil
        }
        return try? JSONDecoder().decode(DoctorReport.self, from: data)
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
    static func scan(path: String? = nil, excludes: [String] = []) throws -> ScanReport {
        let flags = excludes.flatMap { ["--exclude", $0] }
        guard let data = run(["scan", "--format", "ndjson"] + flags + (path.map { [$0] } ?? [])) else {
            throw ScanReportError.noSummary
        }
        return try ScanReport.parse(data)
    }

    /// Prompt-free: `list` reads envelope headers only. `--all` adds the
    /// migrate backups so the window can count them.
    static func vaultList() throws -> VaultListing {
        guard let data = run(["vault", "list", "--all", "--format", "json"]) else {
            throw CLIError.failed("jit vault list produced no output")
        }
        return try JSONDecoder().decode(VaultListing.self, from: data)
    }

    /// Prompt-free: archived versions by stamp, nothing decrypted.
    static func vaultHistory(_ path: String) throws -> VaultHistory {
        guard let data = run(["vault", "history", path, "--format", "json"]) else {
            throw CLIError.failed("jit vault history produced no output")
        }
        return try JSONDecoder().decode(VaultHistory.self, from: data)
    }

    /// `jit vault get` with stdout piped: jit prints the bare value and a
    /// newline, and keeps its footer for a terminal's stderr, so the bytes
    /// need no parsing. The CLI's own Touch ID gates it. The pipe's Data is
    /// moved into a `SecretBuffer` and zeroed; the buffer is the only copy
    /// the app holds, and the caller wipes it when the reveal ends.
    static func reveal(_ path: String) -> Result<SecretBuffer, Error> {
        guard let jit = executable else {
            return .failure(CLIError.notInstalled)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jit)
        process.arguments = ["vault", "get", path]
        process.environment = environment
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
        var data = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            data.resetBytes(in: 0 ..< data.count)
            let text = (String(bytes: stderr, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(CLIError.failed(text.split(separator: "\n").last.map(String.init) ?? ""))
        }
        if data.last == UInt8(ascii: "\n") {
            data[data.count - 1] = 0
            data.removeLast()
        }
        return .success(SecretBuffer(consuming: &data))
    }

    /// A GUI app's PATH lacks the Homebrew prefixes, and `jit vault link`
    /// looks up the 1Password CLI on PATH; hand every jit the same PATH a
    /// terminal would give it.
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
        return env
    }

    /// Whether the 1Password CLI is where `jit vault link` will look for it.
    static var onePasswordCLIInstalled: Bool {
        ["/opt/homebrew/bin/op", "/usr/local/bin/op"].contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs a settings command and returns its last line, or the error. Both
    /// restart the service, and `consent off` puts the CLI's own Touch ID
    /// prompt on screen, so the call may take a while; callers run it off
    /// the main thread.
    static func apply(_ arguments: [String]) -> Result<String, Error> {
        execute(arguments).map { $0.split(separator: "\n").last.map(String.init) ?? "" }
    }

    /// Runs jit with `arguments`, feeding `stdin` when given (a secret value
    /// or a passphrase, for a `--stdin` command), and returns everything it
    /// printed. Touch ID, when the command needs it, is the CLI's own
    /// prompt and works from here as it does from a terminal; what does
    /// not work is a y/N or a hidden prompt, so callers pass --yes and
    /// --stdin and never run a command that would stop to ask.
    static func execute(_ arguments: [String], stdin: String? = nil) -> Result<String, Error> {
        guard let jit = executable else {
            return .failure(CLIError.notInstalled)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jit)
        process.arguments = arguments
        process.environment = environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        let input = Pipe()
        process.standardInput = input
        do {
            try process.run()
        } catch {
            return .failure(error)
        }
        if let stdin {
            input.fileHandleForWriting.write(Data((stdin + "\n").utf8))
        }
        try? input.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus == 0 {
            return .success(text)
        }
        return .failure(CLIError.failed(text.split(separator: "\n").last.map(String.init) ?? ""))
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
