// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Runs the installed `jit` for the one read-only report the panel needs.
/// Resolved from PATH the way a shell would, with the Homebrew prefix as the
/// fallback a GUI app's PATH usually lacks.
enum JitCLI {
    static let candidates = ["/opt/homebrew/bin/jit", "/usr/local/bin/jit"]

    static func status() -> CLIStatus? {
        guard let jit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jit)
        process.arguments = ["status", "--format", "json"]
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
        return try? JSONDecoder().decode(CLIStatus.self, from: data)
    }
}
