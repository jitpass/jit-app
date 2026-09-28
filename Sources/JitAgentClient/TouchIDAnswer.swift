// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What a failed command's words say about the Touch ID it asked for.
public enum TouchIDAnswer {
    /// The person said no (Cancel, or closed the prompt): the command did
    /// what was asked of it, which was nothing. Not a failure to report in
    /// red. jit words it "authentication canceled by user"; macOS's code is
    /// LAErrorUserCancel; both spellings of cancel are matched, as Doctor's
    /// outcome does.
    public static func wasCancelled(_ output: String) -> Bool {
        let text = output.lowercased()
        return text.contains("cancel")
    }
}
