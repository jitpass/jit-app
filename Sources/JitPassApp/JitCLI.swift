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
    static var executable: String? {
        CommandLineTool.runnableJit(in: Bundle.main.bundleURL)
    }

    /// Every `jit status` run is itself a line in `jit audit`, so the panel
    /// reads it at most once per statusCacheTTL rather than on every open.
    /// Read and written from the main thread and from detached tasks
    /// alike, so only under statusLock. The `jit` run itself is outside it.
    private nonisolated(unsafe) static var cachedStatus: (at: Date, value: CLIStatus?)?
    private static let statusLock = NSLock()
    static let statusCacheTTL: TimeInterval = 30

    /// Drops the cached status, for after something changed the vault.
    static func forgetStatus() {
        statusLock.withLock { cachedStatus = nil }
    }

    static func status() -> CLIStatus? {
        let cached = statusLock.withLock { cachedStatus }
        if let cached, Date().timeIntervalSince(cached.at) < statusCacheTTL {
            return cached.value
        }
        let value = run(["status", "--format", "json"]).flatMap { try? JSONDecoder().decode(CLIStatus.self, from: $0) }
        statusLock.withLock { cachedStatus = (Date(), value) }
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

    /// A whole-machine scan. Read-only in every mode, and prompt-free
    /// unless `deep`: `jit scan --deep` reads the vault first, which is a
    /// Touch ID when the service holds no session — so deep runs only from
    /// a click, never from the schedule. It takes seconds, so callers run it
    /// off the main thread.
    static func scan(path: String? = nil, excludes: [String] = [], deep: Bool = false) throws -> ScanReport {
        let flags = excludes.flatMap { ["--exclude", $0] } + (deep ? ["--deep"] : [])
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

    /// Who uses each secret, from profiles in any project folder (`--users`,
    /// jit 2.3.3). It searches home, so it runs off the main thread and
    /// apart from the quick listing; nil on an older engine.
    static func vaultUsers() -> VaultUsersListing? {
        guard let data = run(["vault", "list", "--format", "json", "--users"]) else {
            return nil
        }
        return try? JSONDecoder().decode(VaultUsersListing.self, from: data)
    }

    /// Prompt-free: the wrap manifest, profile files, symlinks and envelope
    /// headers. `--all` adds the catalog so the window can say "installed,
    /// not wrapped", and `--discover` looks for each unwrapped tool's key
    /// where `jit wrap` would (its config files, then its own export
    /// command), reporting where and never what.
    static func toolList() throws -> ToolListing {
        // A jit before 1.6.1 has no --discover and prints usage instead of
        // JSON; the listing without it is the same shape, minus the key
        // discovery, and the window says "not checked" for those rows.
        for arguments in [["wrap", "list", "--all", "--discover", "--format", "json"], ["wrap", "list", "--all", "--format", "json"]] {
            if let data = run(arguments), let listing = try? JSONDecoder().decode(ToolListing.self, from: data) {
                return listing
            }
        }
        throw CLIError.failed("jit wrap list produced no listing")
    }

    /// Decrypts every secret to compare them: an unlock and one consent per
    /// gated class, all the CLI's. Off the main thread.
    static func vaultDuplicates() -> Result<VaultDuplicates, Error> {
        execute(["vault", "duplicates", "--format", "json"]).flatMap { text in
            Result { try JSONDecoder().decode(VaultDuplicates.self, from: Data(text.utf8)) }
        }
    }

    /// Prompt-free: profile manifests and envelope headers only.
    static func vaultOrphans() throws -> VaultOrphans {
        guard let data = run(["vault", "orphans", "--format", "json"]) else {
            throw CLIError.failed("jit vault orphans produced no output")
        }
        return try JSONDecoder().decode(VaultOrphans.self, from: data)
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
        let collected = collect(err)
        var data = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = collected()
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
    /// terminal would give it. The shim dir goes first, as the rc line
    /// puts it, so doctor's "shim dir on PATH" check and the tool listing's
    /// installed-path lookup describe the user's shell, not the app's.
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = LoginShell.mergedPath(login: LoginShell.path, app: env["PATH"] ?? "/usr/bin:/bin")
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
        invoke(arguments, stdin: stdin).flatMap { outcome in
            outcome.status == 0
                ? .success(outcome.output)
                : .failure(CLIError.failed(outcome.output.split(separator: "\n").last.map(String.init) ?? ""))
        }
    }

    /// What one run printed and how it exited.
    struct Outcome: Sendable {
        var status: Int32
        var output: String
    }

    /// `execute` without the reduction to a last line: everything the
    /// command printed, and its exit status, success or not. For a result
    /// the user reads in full, such as a deletion's.
    static func invoke(_ arguments: [String], stdin: String? = nil) -> Result<Outcome, Error> {
        guard let jit = executable else {
            return .failure(CLIError.notInstalled)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jit)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
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
        return .success(Outcome(status: process.terminationStatus, output: text))
    }

    /// A catalog check (`vercel whoami`), for Verify: its exit status and
    /// everything it printed, success or not. The line is the catalog's,
    /// never the user's. Run through the shims on PATH, so a wrapped tool
    /// gets jit's key.
    /// `keep` false (a check that prints a secret) sends the output to
    /// /dev/null: the app never reads it, so it can't show or hold it.
    static func check(_ line: String, keep: Bool = true) -> Result<Outcome, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", line]
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        let out = Pipe()
        if keep {
            process.standardOutput = out
            process.standardError = out
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failure(error)
        }
        try? out.fileHandleForWriting.close()
        let data = keep ? out.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        let text = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(Outcome(status: process.terminationStatus, output: text))
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
        // The same PATH as every other spawn: doctor checks for the 1Password
        // CLI with a PATH lookup, and a GUI PATH without /opt/homebrew/bin
        // had it reporting "op CLI is not installed" on a Mac that has it.
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
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

extension JitCLI {
    /// Whether the jit this app runs is its own helper, the only one that
    /// can reach the Secure Enclave. A dev build's Homebrew jit is not.
    /// Read once: the bundle does not change under a running app.
    static let isBundledHelper = CommandLineTool.runsBundledJit(in: Bundle.main.bundleURL)
}
