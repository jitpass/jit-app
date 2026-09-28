// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What a failed command's words say about the Touch ID it asked for.
public enum TouchIDAnswer {
    /// The person said no (Cancel, or closed the prompt), or macOS dismissed
    /// it: the command did what was asked of it, which was nothing. Not a
    /// failure to report in red. Both of jit's Touch ID paths wrap the
    /// answer as "local authentication failed: …": the Secure Enclave's
    /// "…: canceled", and the keychain's with LocalAuthentication's own
    /// words ("Canceled by user.", "Canceled by another authentication.").
    /// A bare "canceled" is never enough: Go's "context canceled" is a
    /// failure, and says so.
    public static func wasCancelled(_ output: String) -> Bool {
        let text = output.lowercased()
        if text.contains("laerrorusercancel") || text.contains("laerrorsystemcancel") || text.contains("laerrorappcancel") {
            return true
        }
        guard let range = text.range(of: "local authentication failed") else {
            return false
        }
        let after = text[range.upperBound...]
        return after.contains("canceled") || after.contains("cancelled")
    }
}
