// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Consent brokering: the agent shows this app each disclosed challenge
/// while it is connected as a broker (see `AgentClient.subscribe`).
///
/// An agent that knows this app shows requests beside the Touch ID marks
/// them `touchIDFollows` (jitpass/jit#200): its Touch ID is appearing now,
/// the menu bar panel opens beside it with the request on top, and the only
/// answer the app can give is Deny, which takes the Touch ID down. An older
/// agent still waits for the app's answer first, and gets the sheet: Allow
/// only lets it show its own Touch ID; deny refuses without one. Either
/// way the app never approves anything itself.
extension StatusItemController {
    /// How long the answer's line stays before the panel closes (D3 of the
    /// plan), and only when the app opened the panel itself.
    static let outcomeHold: TimeInterval = 3

    var consentActions: ConsentActions {
        ConsentActions(
            allow: { [weak self] id in self?.answerConsent(id, allow: true) },
            deny: { [weak self] id in self?.answerConsent(id, allow: false) }
        )
    }

    /// A `pending` event from the stream. This app's own requests (a grant
    /// it just asked for) and the jit processes it spawned for a click need
    /// no explaining: a dialog here already did. Beside the Touch ID they
    /// are only marked shown, so the dialog appears at once; an older agent
    /// is answered allow, which still only leads to its Touch ID.
    func receive(pending event: SessionEvent) {
        guard let request = ConsentRequest(event: event) else {
            return
        }
        let ours = request.pid == ProcessInfo.processInfo.processIdentifier || request.pid.map(JitCLI.spawned.contains) == true
        let handling = request.handling(ours: ours)
        switch handling {
        case .markShown:
            markShown(request.id)
        case .allow:
            answerConsent(request.id, allow: true)
        case .showBeside, .showSheet:
            if !model.consentRequests.contains(where: { $0.id == request.id }) {
                model.consentRequests.append(request)
            }
            if handling == .showBeside {
                model.consentOutcome = nil
                render()
                showBeside()
                markShown(request.id)
            } else {
                render()
                consentWindow.present()
            }
        }
    }

    /// An outcome for a request this app may still show: the agent answered
    /// it (the fingerprint, Deny, the dialog's Cancel, or its own timeout).
    /// A request shown beside its Touch ID says how it ended, once, in the
    /// block's place; a combined approval and unlock both carry its id, and
    /// only the first says anything.
    func resolve(_ event: SessionEvent) {
        guard let id = event.consentID else {
            return
        }
        let beside = model.consentRequests.first { $0.id == id && $0.touchIDFollows }
        model.consentRequests.removeAll { $0.id == id }
        render()
        if let beside {
            model.consentOutcome = ConsentOutcome(
                id: id, program: beside.program, launchedBy: beside.launchedBy,
                allowed: ConsentRequest.allowed(by: event), date: event.date
            )
            refitSoon()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.outcomeHold) { [weak self] in
                self?.endOutcome(id)
            }
        }
        if !model.consentRequests.contains(where: { !$0.touchIDFollows }) {
            consentWindow.orderOut(nil)
        }
    }

    /// Re-reads what is waiting, on every (re)connect: a request raised
    /// while no stream was open is only in `consent_list`. The sheet comes
    /// back for a request waiting on an answer. One beside its Touch ID is
    /// only listed and marked shown: this runs as the human opens the panel,
    /// which must not then open itself.
    func syncConsentRequests() {
        let waiting = ((try? client.consentList()) ?? []).compactMap(ConsentRequest.init(event:))
        model.consentRequests = waiting
        render()
        for request in waiting where request.touchIDFollows {
            markShown(request.id)
        }
        if waiting.contains(where: { !$0.touchIDFollows }) {
            consentWindow.present()
        } else {
            consentWindow.orderOut(nil)
        }
    }

    func openConsent() {
        panel.dismiss()
        consentWindow.present()
    }

    /// Deny in the Asking block. The request stays on screen until the
    /// agent's outcome arrives, which is what says it was refused: a Deny
    /// that came a moment after the fingerprint is told the request is gone,
    /// and the line then says Allowed, which is the truth.
    func denyBeside(_ id: String) {
        let client = client
        Task.detached {
            try? client.answerConsent(id: id, allow: false)
        }
    }

    /// On the next turn of the run loop, once the panel's content has taken
    /// the request in, so the panel opens at the size that fits it.
    private func showBeside() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = item.button else {
                return
            }
            panel.showBeside(under: button)
        }
    }

    private func refitSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.panel.refit()
        }
    }

    /// Tells the agent the request is drawn, on the next turn of the run
    /// loop, after the panel's frame has reached the window server. It grants
    /// nothing; without it the Touch ID waits a quarter of a second.
    private func markShown(_ id: String) {
        let client = client
        DispatchQueue.main.async {
            Task.detached {
                try? client.consentShown(id: id)
            }
        }
    }

    /// The answer's line has been said. The panel closes if the app opened
    /// it and nothing new is asking; a panel the human opened stays.
    private func endOutcome(_ id: String) {
        guard model.consentOutcome?.id == id else {
            return
        }
        model.consentOutcome = nil
        guard model.consentRequests.isEmpty else {
            return
        }
        if panel.openedForConsent {
            panel.dismiss()
        } else {
            refitSoon()
        }
    }

    private func answerConsent(_ id: String, allow: Bool) {
        let client = client
        model.consentRequests.removeAll { $0.id == id }
        render()
        if model.consentRequests.isEmpty {
            consentWindow.orderOut(nil)
        }
        Task.detached {
            // A request that already ended (timed out, answered elsewhere)
            // is refused by the agent; there is nothing to show for that.
            try? client.answerConsent(id: id, allow: allow)
        }
    }
}
