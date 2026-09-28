// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What a failed Doctor step said, as one line under the header.
public enum DoctorFailureLine {
    /// jit's whole message, unwrapped: jit wraps its own output, so the
    /// last line alone was often only the end of a sentence (a bare
    /// command path). Named after the step unless jit already named it.
    public static func make(output: String, argv: [String], status: Int32) -> String {
        let text = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let command = "jit " + argv.joined(separator: " ")
        guard !text.isEmpty else {
            return command + ": exit \(status)"
        }
        return text.hasPrefix("jit ") ? text : command + ": " + text
    }

    /// jit refused because only the signed jit inside JitPass.app can reach
    /// the Secure Enclave: running the same step again cannot change that.
    public static func needsTheInstalledApp(_ output: String) -> Bool {
        let text = output.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.contains("only the jit inside jitpass.app can reach it")
            || text.contains("can't use the secure enclave")
    }
}
