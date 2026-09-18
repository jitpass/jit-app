// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

extension JitCLI {
    /// What Remove would do: `jit uninstall --restore --dry-run --format
    /// json`. Read-only and free of any prompt. Off the main thread.
    static func uninstallPlan() -> Result<UninstallPlan, Error> {
        execute(OffboardingPlan.planCommand).flatMap { text in
            Result { try UninstallPlan.parse(Data(text.utf8)) }
        }
    }

    /// How a streamed uninstall ended.
    enum UninstallOutcome: Equatable {
        case removed(problems: [String])
        /// Files could not be put back, so jit deleted nothing.
        case couldNotRestore([UninstallEvent.Failure])
        /// Anything else: a declined Touch ID, a jit that would not start.
        case failed(String)
    }

    /// Runs `jit uninstall … --format ndjson`, handing each event to
    /// `onEvent` as its line arrives, so the checklist ticks on what jit has
    /// really done. Touch ID is jit's own prompt. Off the main thread.
    static func uninstall(_ arguments: [String], onEvent: @escaping @Sendable (UninstallEvent) -> Void) -> UninstallOutcome {
        guard let jit = executable else {
            return .failed("jit is not installed")
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
            return .failed(Format.error(error))
        }
        spawned.insert(process.processIdentifier)
        defer { spawned.remove(process.processIdentifier) }

        var failures: [UninstallEvent.Failure]?
        var problems: [String]?
        eachLine(of: out.fileHandleForReading) { line in
            guard let event = UninstallEvent.parse(line: line) else {
                return
            }
            if case let .failed(list) = event {
                failures = list
            }
            if case let .done(list) = event {
                problems = list
            }
            onEvent(event)
        }
        let complaint = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        if let failures {
            return .couldNotRestore(failures)
        }
        if let problems {
            return .removed(problems: problems)
        }
        let last = complaint.split(separator: "\n").last.map(String.init) ?? ""
        return .failed(last.isEmpty ? "jit stopped without saying why" : last)
    }

    /// Calls `body` with each newline-terminated line as it arrives, until
    /// the writer closes the pipe.
    private static func eachLine(of handle: FileHandle, _ body: (String) -> Void) {
        var pending = Data()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty {
                return
            }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                body(String(data: pending[pending.startIndex ..< newline], encoding: .utf8) ?? "")
                pending.removeSubrange(pending.startIndex ... newline)
            }
        }
    }
}
