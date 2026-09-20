// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// How a card's fix ended, for the few seconds the card shows it: done
/// (green, "okta-mcp-server starts again") until the recheck takes the
/// card away, or failed (red, what jit said, and Try Again). Worded here
/// from what ran and what jit printed; there is no undo to offer, so none
/// is.
public struct DoctorOutcome: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case done, failed
    }

    /// The card's id, or a row's.
    public var key: String
    /// The card as it was, shown after a recheck no longer lists it.
    public var card: DoctorCard
    /// What ran, for Try Again.
    public var button: DoctorButton
    public var state: State
    public var title: String
    public var line: String?
    /// jit's own last words, when it said something. Shown under the line
    /// in the app's own type — never in a terminal window, which is where
    /// they used to go: a black pane over a window that already knew.
    public var said: String?
    public var at: Date

    public init(
        key: String, card: DoctorCard, button: DoctorButton, state: State, title: String, line: String?,
        said: String? = nil, at: Date = Date()
    ) {
        self.key = key
        self.card = card
        self.button = button
        self.state = state
        self.title = title
        self.line = line
        self.said = said
        self.at = at
    }

    /// How long a done card stays before the recheck may take it.
    public static let doneSeconds: TimeInterval = 3
}

public extension DoctorCard {
    /// The outcome of `button` on this card (or on its row `key`): how
    /// many of its steps finished, everything jit printed, and whether it
    /// failed. `subject` names a row instead of the card.
    func outcome(
        key: String, button: DoctorButton, completed: Int, output: String, failed: Bool, subject: String? = nil,
        at: Date = Date()
    ) -> DoctorOutcome {
        let total = button.steps.count
        let values = total > 0 && button.steps.allSatisfy {
            if case .secret = $0.input {
                true
            } else {
                false
            }
        }
        let what = subject ?? self.subject
        let last = output.split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard failed else {
            let fixesTools = button == primary && !tools.isEmpty
            let title = fixesTools ? "\(BoardText.list(tools)) \(tools.count == 1 ? "starts" : "start") again" : "Done"
            var line: String? = last.isEmpty ? nil : last
            if values {
                line = (total == 1 ? "1 value set." : "\(total) values set.")
                if fixesTools, restartsInEditor {
                    line? += " Restart \(tools.count == 1 ? "it" : "them") in your editor to pick \(total == 1 ? "it" : "them") up."
                }
            }
            return DoctorOutcome(key: key, card: self, button: button, state: .done, title: title, line: line, at: at)
        }
        let cancelled = output.lowercased().contains("cancel")
        // What the app can say goes on the line; what jit said goes in its
        // own box under it. Quoting jit inside the sentence ("jit says: …")
        // made one voice of two, and the only place to read the whole of
        // what it said was a terminal window that no longer opens.
        let whole = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let said = whole.isEmpty || cancelled ? nil : whole
        let title: String
        var line: String?
        if completed == 0 {
            title = cancelled ? "\(what): nothing was changed" : "\(what): didn't finish"
            line = cancelled ? "Touch ID was cancelled. The finding stays until you try again."
                : (said == nil ? "jit stopped without saying why." : nil)
        } else {
            title = "\(what): stopped partway"
            let done = values ? "\(completed) of \(total) values set." : "\(completed) of \(total) steps done."
            line = done + (cancelled ? " Touch ID was cancelled for the rest." : "")
        }
        return DoctorOutcome(key: key, card: self, button: button, state: .failed, title: title, line: line, said: said, at: at)
    }
}
