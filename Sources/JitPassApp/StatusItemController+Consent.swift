// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Consent brokering: the agent shows this app each disclosed challenge
/// while it is connected as a broker (see `AgentClient.subscribe`).
///
/// An agent that knows this app shows requests beside the Touch ID marks
/// them `touchIDFollows` (jitpass/jit#200): its Touch ID is appearing now,
/// and nothing of this app opens by itself. The Touch ID dialog says what is
/// asked and is where the human answers (Meni, 2026-09-29, after the live
/// test: first the whole panel opened beside it, then a small popup, and
/// both were one thing too many). The menu bar mark turns amber, and the
/// panel, when the human opens it, has the request on top with its command
/// line and Deny, which takes the Touch ID down. An older agent still waits
/// for the app's answer first, and gets the sheet: Allow only lets it show
/// its own Touch ID; deny refuses without one. Either way the app never
/// approves anything itself.
extension StatusItemController {
    /// How long the answer's line stays in an open panel.
    static let outcomeHold: TimeInterval = 3

    var consentActions: ConsentActions {
        ConsentActions(
            allow: { [weak self] id in self?.answerConsent(id, allow: true) },
            deny: { [weak self] id in self?.answerConsent(id, allow: false) }
        )
    }

    /// A `pending` event from the stream. This app's own requests (a grant
    /// it just asked for) and the jit processes it spawned for a click need
    /// no explaining: a dialog here already did. Beside the Touch ID every
    /// request is marked shown at once, so the dialog never waits for this
    /// app, and the app's own are not listed; an older agent is answered
    /// allow for them, which still only leads to its Touch ID.
    func receive(pending event: SessionEvent) {
        guard let request = ConsentRequest(event: event) else {
            return
        }
        let handling = request.handling(ours: isOurs(request))
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
                markShown(request.id)
                holdOpenPanel()
            } else {
                render()
                consentWindow.present()
            }
        }
    }

    /// An outcome for a request this app may still show: the agent answered
    /// it (the fingerprint, Deny, the dialog's Cancel, or its own timeout).
    /// In an open panel, a request beside its Touch ID says how it ended,
    /// once, in the block's place; a combined approval and unlock both carry
    /// its id, and only the first says anything.
    func resolve(_ event: SessionEvent) {
        guard let id = event.consentID else {
            return
        }
        let beside = model.consentRequests.first { $0.id == id && $0.touchIDFollows }
        model.consentRequests.removeAll { $0.id == id }
        render()
        if !model.consentRequests.contains(where: \.touchIDFollows) {
            panel.releaseConsentHold()
        }
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
    /// only listed and marked shown. The app's own request beside its Touch
    /// ID is marked shown and never listed, as on arrival.
    ///
    /// It is also how an outcome the stream missed (a lag, a reconnect) is
    /// noticed: the request is simply gone, and the panel closes on an
    /// outside click again.
    func syncConsentRequests() {
        let listed = ((try? client.consentList()) ?? []).compactMap(ConsentRequest.init(event:))
        let waiting = listed.filter { !($0.touchIDFollows && isOurs($0)) }
        model.consentRequests = waiting
        render()
        for request in listed where request.touchIDFollows {
            markShown(request.id)
        }
        if !waiting.contains(where: \.touchIDFollows) {
            panel.releaseConsentHold()
        }
        refitSoon()
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

    /// A request from this app, or from a jit it started for a click: a
    /// dialog in the app already explained it.
    private func isOurs(_ request: ConsentRequest) -> Bool {
        request.pid == ProcessInfo.processInfo.processIdentifier || request.pid.map(JitCLI.spawned.contains) == true
    }

    /// After the icon toggled the panel, and when a request arrives: a panel
    /// the human has open while a request is beside the Touch ID stays
    /// through a click on the dialog, so Deny and the command line do not
    /// vanish with it, and fits its contents once SwiftUI has taken them in.
    /// A closed panel stays closed.
    func holdOpenPanel() {
        if panel.isVisible, model.consentRequests.contains(where: \.touchIDFollows) {
            panel.holdForConsent()
        }
        refitSoon()
    }

    private func refitSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.panel.refit()
        }
    }

    /// Tells the agent not to wait for this app: its Touch ID appears at
    /// once. It grants nothing; without it the dialog waits a quarter of a
    /// second.
    private func markShown(_ id: String) {
        let client = client
        Task.detached {
            try? client.consentShown(id: id)
        }
    }

    /// The answer's line has been said.
    private func endOutcome(_ id: String) {
        guard model.consentOutcome?.id == id else {
            return
        }
        model.consentOutcome = nil
        refitSoon()
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
