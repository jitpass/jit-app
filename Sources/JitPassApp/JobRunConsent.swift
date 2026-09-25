// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// A brokered job run (the Jobs mockup, frame G2): which job, the exact
/// command, the folder and whether it is unchanged, who asked, and which
/// secrets stay hidden. It replaces the credential sheet for a job, whose
/// "remembered until the vault locks" was false: an each-time job asks on
/// every run. As with every brokered prompt, Allow only lets the service go
/// on to its own Touch ID; Deny refuses without one.
struct JobRunConsent: View {
    let request: ConsentRequest
    let job: JobStatus?
    let count: Int
    let actions: ConsentActions

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            HStack(alignment: .top, spacing: Win.s4) {
                StateDot(tint: Color(StatusMark.amber)).padding(.top, 5)
                VStack(alignment: .leading, spacing: Win.s2) {
                    Text(Format.jobRunTitle(request)).font(Win.cardTitle)
                    Text(Format.jobRunSentence(request, job: job)).font(Design.Text.row).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if count > 1 {
                    Text("1 of \(count)").font(Win.rowFact).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: Win.s4) {
                if let job {
                    fact("Runs") {
                        Text(JobDraft.join(job.argv)).font(Win.command).textSelection(.enabled)
                            .padding(.horizontal, Win.s4).padding(.vertical, Win.s3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WindowSurface.verbatim, in: RoundedRectangle(cornerRadius: Win.control, style: .continuous))
                        Text(Format.jobRunFolder(job)).font(Win.rowFact).foregroundStyle(.secondary)
                    }
                    fact("Secrets") { Text(Format.jobRunSecrets(job)).font(Win.sub).foregroundStyle(.secondary) }
                }
                fact("Asked by") {
                    Text((request.launchedBy ?? request.program) +
                        (request.identifiedByScan ? " · found by a process scan" : " · identified by the kernel"))
                        .font(Win.sub).foregroundStyle(request.identifiedByScan ? Color(StatusMark.amber) : .secondary)
                }
            }
            VStack(alignment: .leading, spacing: Win.s2) {
                Rectangle().fill(WindowSurface.separator).frame(height: 1).padding(.bottom, Win.s4)
                ForEach(Format.jobRunNotes(request), id: \.self) { line in
                    Text("• " + line).font(Win.rowFact).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Win.s4) {
                Text("The service decides, not this app.").font(Win.sub).foregroundStyle(.secondary)
                Spacer()
                Button("Deny") { actions.deny(request.id) }.buttonStyle(AppButton(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Allow with Touch ID") { actions.allow(request.id) }.buttonStyle(AppButton(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func fact(_ label: String, @ViewBuilder _ value: () -> some View) -> some View {
        HStack(alignment: .top, spacing: Win.s5) {
            Text(label).font(Win.sub).foregroundStyle(.secondary).frame(width: 62, alignment: .trailing).padding(.top, 3)
            VStack(alignment: .leading, spacing: Win.s3) { value() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
