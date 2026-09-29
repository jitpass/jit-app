// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// A request the agent shows beside its Touch ID (jitpass/jit#200), on top
/// of the menu bar panel: the consent sheet's facts in the agent's words,
/// and Deny. There is no Allow. The fingerprint allows it, and Deny takes
/// the Touch ID down. The app decides nothing: Deny only refuses.
struct AskingBlock: View {
    let request: ConsentRequest
    let job: JobStatus?
    let deny: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.five) {
            VStack(alignment: .leading, spacing: Design.Space.two) {
                Text(Format.askingTitle(request)).font(Design.Text.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(request.isJobRun ? Format.jobRunSentence(request, job: job) : request.headline)
                    .font(Design.Text.cardNote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Design.Space.three) {
                if request.isJobRun {
                    jobFacts
                } else {
                    credentialFacts
                }
            }
            if request.priorRefusals > 0 {
                Text(Format.askingRefusals(request.priorRefusals))
                    .font(Design.Text.rowFact).foregroundStyle(Color(StatusMark.amber))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(Format.askingNote).font(Design.Text.rowFact).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Design.Space.four) {
                Text(Format.askingAllows).font(Design.Text.rowFact).foregroundStyle(.secondary)
                Spacer()
                Button("Deny") { deny(request.id) }.buttonStyle(AppButton(kind: .secondary))
            }
        }
        .padding(Design.Space.five)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Surface.card, in: RoundedRectangle(cornerRadius: Design.Radius.callout, style: .continuous))
        .padding(.horizontal, Design.Space.three)
        .padding(.bottom, Design.Space.three)
    }

    @ViewBuilder
    private var credentialFacts: some View {
        if let command = request.command {
            fact("Command") {
                // Three lines, then it scrolls, so Deny never leaves the
                // panel; it says so when there is more.
                CappedText(text: command, font: Design.Text.commandSmall, lines: 3, saysMore: true)
            }
        }
        if let launchedBy = request.launchedBy {
            fact("Launched by") { Text(launchedBy) }
        }
        identified
        fact("Asked") { Text(Format.clock(request.date)) }
    }

    @ViewBuilder
    private var jobFacts: some View {
        if let job {
            fact("Runs") {
                CappedText(text: JobDraft.join(job.argv), font: Design.Text.commandSmall, lines: 3, saysMore: true)
                Text(Format.jobRunFolder(job)).foregroundStyle(.secondary)
            }
            fact("Secrets") { Text(Format.jobRunSecrets(job)).foregroundStyle(.secondary) }
        }
        fact("Asked by") { Text(request.launchedBy ?? request.program) }
        identified
    }

    /// A weak identity reads as weak, in the sheet's exact words and amber.
    private var identified: some View {
        fact("Identified") {
            Text(Format.askingIdentified(request))
                .foregroundStyle(request.identifiedByScan ? Color(StatusMark.amber) : .primary)
        }
    }

    private func fact(_ label: String, @ViewBuilder _ value: () -> some View) -> some View {
        HStack(alignment: .top, spacing: Design.Space.four) {
            Text(label).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
            VStack(alignment: .leading, spacing: Design.Space.two) { value() }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Design.Text.rowFact)
    }
}

/// The line that replaces the Asking block once the Touch ID is answered,
/// said once before the panel closes. A denial is an answer, not a failure,
/// so it takes no red.
struct ConsentOutcomeRow: View {
    let outcome: ConsentOutcome

    var body: some View {
        HStack(alignment: .top, spacing: Design.Space.five) {
            Image(systemName: outcome.allowed ? "checkmark" : "minus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(outcome.allowed ? Color(StatusMark.green) : .secondary)
                .frame(width: Design.Size.glyph, height: Design.Size.glyph)
            VStack(alignment: .leading, spacing: Design.Space.one) {
                Text(Format.outcomeTitle(outcome)).font(Design.Text.rowName)
                Text(Format.outcomeDetail(outcome)).font(Design.Text.rowFact).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, Design.Space.four)
    }
}

/// A request shown beside its Touch ID, answered: who, and which way. A
/// denial is the human's answer, not a failure, so it takes no red.
struct ConsentOutcome: Equatable {
    let id: String
    let program: String
    let launchedBy: String?
    let allowed: Bool
    let date: Date
}
