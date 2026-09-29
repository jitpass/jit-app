// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

// MARK: - The Asking block (a request shown beside its Touch ID)

extension Format {
    /// The header's second line while the Touch ID is up.
    static func askingSub(count: Int) -> String {
        count > 1 ? "1 of \(count) · Touch ID is open" : "Touch ID is open"
    }

    /// The block's bold line: the program and what it asks for, as the
    /// sheet says it. A job's run keeps its own title.
    static func askingTitle(_ request: ConsentRequest) -> String {
        request.isJobRun ? jobRunTitle(request) : "\(request.program) asks to \(request.purpose)"
    }

    static func askingIdentified(_ request: ConsentRequest) -> String {
        if request.identifiedByScan {
            return "by scanning running processes, not by the kernel; a process running as you could fake this"
        }
        return "by the kernel" + (request.pid.map { ", pid \($0)" } ?? "")
    }

    /// The amber line for a request refused before this session (D4 of the
    /// plan): a loop shows as one, without a second step to answer.
    static func askingRefusals(_ count: Int) -> String {
        "Refused \(count) time\(count == 1 ? "" : "s") already this session. Something may be asking in a loop."
    }

    /// The block's one note, replacing the sheet's three: with no Allow, the
    /// first of them ("Allow: macOS asks for Touch ID next") is no longer true.
    static let askingNote = "Deny cancels the Touch ID: the program gets an error and no secret. Both answers are recorded in the audit."

    static let askingAllows = "Touch ID allows it."

    /// The line that replaces the block once the Touch ID is answered.
    static func outcomeTitle(_ outcome: ConsentOutcome) -> String {
        (outcome.allowed ? "Allowed " : "Denied ") + outcome.program
    }

    static func outcomeDetail(_ outcome: ConsentOutcome) -> String {
        guard outcome.allowed else {
            return "It got an error and no secret. It may ask again after a short pause."
        }
        let at = "at " + clock(outcome.date)
        return outcome.launchedBy.map { "launched by \($0), \(at)" } ?? at
    }
}
