// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The request the agent has parked with the app, in full: who asked, what
/// launched it, how it was identified, and what each answer does. The app
/// decides nothing here. Allow lets the agent go on to the Touch ID it
/// would have shown anyway; Deny refuses without one.
struct ConsentView: View {
    @ObservedObject var model: MenuModel
    let actions: ConsentActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let request = model.consentRequests.first {
                content(request)
            } else {
                Text("No request is waiting.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(18)
        .frame(width: 500)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
    }

    @ViewBuilder
    private func content(_ request: ConsentRequest) -> some View {
        if request.isJobRun {
            JobRunConsent(
                request: request,
                job: model.jobs.first { $0.name == request.job },
                count: model.consentRequests.count,
                actions: actions
            )
        } else {
            credentialContent(request)
        }
    }

    @ViewBuilder
    private func credentialContent(_ request: ConsentRequest) -> some View {
        header(request)
        facts(request)
        if request.priorRefusals > 0 {
            refusalNote(request.priorRefusals)
        }
        explanation
        HStack {
            Spacer()
            Button("Deny") { actions.deny(request.id) }.keyboardShortcut(.cancelAction)
            Button("Allow with Touch ID") { actions.allow(request.id) }.keyboardShortcut(.defaultAction)
        }
    }

    private func header(_ request: ConsentRequest) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color(StatusMark.amber)).frame(width: 10, height: 10).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(request.program) asks to \(request.purpose)").font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(request.headline).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.consentRequests.count > 1 {
                Text("1 of \(model.consentRequests.count)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func facts(_ request: ConsentRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let command = request.command {
                fact("Command") {
                    Text(command).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let launchedBy = request.launchedBy {
                fact("Launched by") { Text(launchedBy) }
            }
            fact("Identified") {
                if request.identifiedByScan {
                    Text("by scanning running processes, not by the kernel; a process running as you could fake this")
                        .foregroundStyle(Color(StatusMark.amber))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("by the kernel" + (request.pid.map { ", pid \($0)" } ?? ""))
                }
            }
            fact("Asked") { Text(Format.clock(request.date)) }
        }
        .font(.system(size: 13))
    }

    private func refusalNote(_ count: Int) -> some View {
        Text("Refused \(count) time\(count == 1 ? "" : "s") already this session. Something may be asking in a loop.")
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(StatusMark.amber).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("• Allow: macOS asks for Touch ID next. The service decides on that, not this app.")
            Text("• Deny: the program gets an error and no secret. It may ask again after a short pause.")
            Text("• Nothing else changes either way; both answers are recorded in the audit.")
        }
        .font(.subheadline).foregroundStyle(.secondary)
    }

    private func fact(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
            value()
            Spacer(minLength: 0)
        }
    }
}

struct ConsentActions {
    var allow: (String) -> Void = { _ in }
    var deny: (String) -> Void = { _ in }
}
