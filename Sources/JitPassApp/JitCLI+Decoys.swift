// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// `jit decoys expected|expect|unexpect`: prompt-free, and a list either way.
extension JitCLI {
    /// Nil on an engine without the command: no Expected in the window.
    static func decoysExpected() -> ExpectedReaders? {
        guard case let .success(outcome) = invoke(["decoys", "expected", "--format", "json"]), outcome.status == 0 else {
            return nil
        }
        return try? JSONDecoder().decode(ExpectedReaders.self, from: Data(outcome.output.utf8))
    }

    /// Adds (or with `remove`, takes back) one expected reader; the list after.
    static func decoysExpect(_ reader: ExpectedReader, remove: Bool) -> Result<ExpectedReaders, Error> {
        var arguments = ["decoys", remove ? "unexpect" : "expect", reader.program]
        if let file = reader.file {
            arguments += ["--file", file]
        }
        return invoke(arguments + ["--format", "json"]).flatMap { outcome in
            guard outcome.status == 0 else {
                return .failure(CLIError.failed(outcome.output.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            return Result { try JSONDecoder().decode(ExpectedReaders.self, from: Data(outcome.output.utf8)) }
        }
    }
}
