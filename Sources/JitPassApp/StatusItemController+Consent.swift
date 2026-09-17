// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Consent brokering: the agent parks each disclosed challenge with this
/// app while it is connected as a broker (see `AgentClient.subscribe`),
/// the sheet explains it, and the answer goes back with `consent_answer`.
/// Allow only lets the agent show its own Touch ID; deny refuses without
/// one. The app never approves anything itself.
extension StatusItemController {
    var consentActions: ConsentActions {
        ConsentActions(
            allow: { [weak self] id in self?.answerConsent(id, allow: true) },
            deny: { [weak self] id in self?.answerConsent(id, allow: false) }
        )
    }

    /// A `pending` event from the stream. This app's own requests (a grant
    /// it just asked for) are allowed straight through: its sheet already
    /// explained them, and the agent's Touch ID is still to come.
    func receive(pending event: SessionEvent) {
        guard let request = ConsentRequest(event: event) else {
            return
        }
        if request.pid == ProcessInfo.processInfo.processIdentifier {
            answerConsent(request.id, allow: true)
            return
        }
        if !model.consentRequests.contains(where: { $0.id == request.id }) {
            model.consentRequests.append(request)
        }
        render()
        consentWindow.present()
    }

    /// An outcome (approved, denied) for a request the sheet may still show:
    /// the agent answered it, from the app or by its own timeout.
    func resolve(consentID: String) {
        model.consentRequests.removeAll { $0.id == consentID }
        render()
        if model.consentRequests.isEmpty {
            consentWindow.orderOut(nil)
        }
    }

    /// Re-reads what is waiting, on every (re)connect: a request raised
    /// while no stream was open is only in `consent_list`.
    func syncConsentRequests() {
        let waiting = ((try? client.consentList()) ?? []).compactMap(ConsentRequest.init(event:))
        model.consentRequests = waiting
        render()
        if waiting.isEmpty {
            consentWindow.orderOut(nil)
        } else {
            consentWindow.present()
        }
    }

    func openConsent() {
        panel.dismiss()
        consentWindow.present()
    }

    private func answerConsent(_ id: String, allow: Bool) {
        let client = client
        resolve(consentID: id)
        Task.detached {
            // A request that already ended (timed out, answered elsewhere)
            // is refused by the agent; there is nothing to show for that.
            try? client.answerConsent(id: id, allow: allow)
        }
    }
}
