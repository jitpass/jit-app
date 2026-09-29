// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// What the panel shrinks to when a request opens it (the consent mockup,
/// "a small popup, not the whole panel"): who asks for what kind of
/// authority, how sure the identity is, and Deny. The Touch ID dialog
/// beside it carries the full sentence and is where the human approves, so
/// the status rows and menu actions stay out. Clicking the menu bar icon
/// still opens the full panel, with the Asking block on top.
struct AskingPopup: View {
    @ObservedObject var model: MenuModel
    let deny: (String) -> Void
    /// Tells the panel its height changed (Details opened or closed).
    let resized: () -> Void
    @State private var details = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.four) {
            if let request = model.consentRequests.first(where: \.touchIDFollows) {
                asking(request)
            } else if let outcome = model.consentOutcome {
                ConsentOutcomeRow(outcome: outcome)
                    .padding(.horizontal, -14) // the row carries the panel's inset itself
                    .padding(.bottom, -Design.Space.four)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Design.Space.five)
        .frame(width: 300, alignment: .leading)
        .background(VisualEffectBackground(material: .menu, cornerRadius: Design.Radius.panel))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous))
    }

    @ViewBuilder
    private func asking(_ request: ConsentRequest) -> some View {
        HStack(alignment: .top, spacing: 10) {
            StatusMarkView(state: model.state, asking: true, size: 24).padding(.top, 1)
            VStack(alignment: .leading, spacing: Design.Space.one) {
                Text(Format.popupTitle(request)).font(Design.Text.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Format.popupWho(request)).font(Design.Text.rowFact)
                    .foregroundStyle(request.identifiedByScan ? Color(StatusMark.amber) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Group {
            if request.priorRefusals > 0 {
                Text(Format.popupRefusals(request.priorRefusals))
                    .font(Design.Text.rowFact).foregroundStyle(Color(StatusMark.amber))
            }
            if details {
                facts(request)
            }
            HStack(spacing: Design.Space.four) {
                Button {
                    details.toggle()
                    resized()
                } label: {
                    Text(Format.popupDetails + (details ? " ‹" : " ›")).font(Design.Text.rowFact)
                }
                .buttonStyle(AppButton(kind: .plain))
                Spacer()
                Button(Format.AskingLabel.deny) { deny(request.id) }.buttonStyle(AppButton(kind: .primary))
            }
        }
        .padding(.leading, 34) // under the title, past the mark
    }

    private func facts(_ request: ConsentRequest) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.two) {
            if request.isJobRun, let job = model.jobs.first(where: { $0.name == request.job }) {
                fact(Format.AskingLabel.runs, JobDraft.join(job.argv), mono: true)
                fact(Format.AskingLabel.secrets, Format.jobRunSecrets(job))
            } else if let command = request.command {
                fact(Format.AskingLabel.command, command, mono: true)
            }
            if let pid = request.pid {
                fact(Format.popupPID, String(pid))
            }
            fact(Format.AskingLabel.asked, Format.clock(request.date))
        }
    }

    private func fact(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).foregroundStyle(.secondary).frame(width: CGFloat(Design.Size.noteWidth), alignment: .trailing)
            Text(value).font(mono ? Design.Text.commandSmall : Design.Text.rowFact)
                .lineLimit(4).truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Design.Text.rowFact)
    }
}
