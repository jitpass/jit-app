// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// AI Jobs (jit design/agent-jobs.md; the Jobs mockup, frames A and B): the
/// small window. A header that counts; a card per stopped job, amber, sorted
/// first because only the human can answer it; one card of the jobs that are
/// ready; and the AI apps that can ask. A job has no deadline, so each row
/// spends its second line on who ran it last and what happened. Nothing here
/// runs a job: that is what an AI tool does.
struct AIJobsView: View {
    @ObservedObject var model: MenuModel
    let actions: AIJobsActions
    let sheetActions: JobSheetActions

    var body: some View {
        let board = model.jobsBoard
        VStack(spacing: 0) {
            if let banner = model.jobsBanner {
                WindowBanner(tint: Color(model.jobsBannerFailed ? StatusMark.red : StatusMark.green), text: banner)
            }
            VStack(spacing: 0) {
                header(board)
                content(board)
            }
            .measureWindowHeight()
            if !board.isEmpty {
                footer(board)
            }
        }
        .frame(
            minWidth: Win.widthSmall, maxWidth: .infinity,
            minHeight: Win.minimum(Win.heightSmall), maxHeight: .infinity,
            alignment: .top
        )
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onPreferenceChange(WindowHeightKey.self) { height in
            actions.fit(height + Self.chrome(banner: model.jobsBanner != nil, footer: !board.isEmpty))
        }
        .sheet(isPresented: $model.jobSheet) {
            JobSheetView(model: model, actions: sheetActions)
        }
        .onAppear(perform: actions.reload)
    }

    /// The regions outside the measured stack.
    static func chrome(banner: Bool, footer: Bool) -> CGFloat {
        (banner ? 39 : 0) + (footer ? 37 : 0)
    }

    private func header(_ board: JobsBoard) -> some View {
        HStack(alignment: .center, spacing: Win.s5) {
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(Format.jobsHeadline(board)).font(Win.head)
                Text(Format.jobsSubline(board)).font(Win.sub).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Win.s5)
            Button("New AI Job…", action: actions.newJob).buttonStyle(AppButton(kind: .primary))
        }
        .windowRegion(rule: !board.isEmpty)
    }

    @ViewBuilder private func content(_ board: JobsBoard) -> some View {
        if board.isEmpty, board.proposals.isEmpty {
            WindowEmptyState(tint: Color(StatusMark.green), title: Format.jobsEmptyTitle, message: Format.jobsEmptyMessage) {
                EmptyView()
            }
        } else {
            ScrollView {
                VStack(spacing: Win.s5) {
                    ForEach(board.proposals) { proposal in
                        proposalCard(proposal)
                    }
                    ForEach(board.stopped) { job in
                        stoppedCard(job)
                    }
                    if !board.ready.isEmpty {
                        JobsCard(eyebrow: "Ready", tint: Color(StatusMark.green)) {
                            ForEach(Array(board.ready.enumerated()), id: \.element.id) { index, job in
                                jobRow(job, last: index == board.ready.count - 1)
                            }
                        }
                    }
                    appsCard
                }
                .padding(Win.s6)
            }
        }
    }

    /// Only the human can answer a stopped job, so it sits first, amber, and
    /// says what stopped it in the service's own words.
    private func stoppedCard(_ job: JobStatus) -> some View {
        AppCard(
            eyebrow: Format.jobStoppedEyebrow(job),
            eyebrowTint: Color(StatusMark.amber),
            title: Format.jobStoppedTitle(job),
            note: Format.jobStoppedNote(job)
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                jobRow(job, last: true)
            }
        }
    }

    /// An agent's proposal waiting for the human. Not drawn in the mockup,
    /// whose proposal lives only in its sheet (frame D): once that sheet is
    /// closed, the proposal still waits and the headline counts it, so it
    /// needs a place to be seen and reopened.
    private func proposalCard(_ proposal: JobProposal) -> some View {
        AppCard(
            eyebrow: "Proposed",
            eyebrowTint: Color(StatusMark.amber),
            title: Format.proposalTitle(proposal),
            note: proposal.why.map { "“\($0)” " + Format.proposalWhyHint(proposal) }
        ) {
            Button("Review…") { actions.review(proposal) }.buttonStyle(AppButton(kind: .secondary))
        } rows: {
            AppCardRows {
                AppRow(
                    name: proposal.name,
                    detail: "· " + JobDraft.join(proposal.spec.argv),
                    fact: Format.proposalFact(proposal),
                    last: true
                ) {
                    EmptyView()
                }
            }
        }
    }

    private func jobRow(_ job: JobStatus, last: Bool) -> some View {
        AppRow(name: job.name, detail: Format.jobCommand(job), fact: Format.jobFact(job), last: last) {
            Button("Remove…") { actions.remove(job) }.buttonStyle(AppButton(kind: .quiet))
        }
    }

    /// Which AI apps can reach the jobs. Claude Desktop only when it is
    /// installed, since connecting is the one thing that row can do; terminal
    /// agents always can, through `jit job run`.
    private var appsCard: some View {
        JobsCard(eyebrow: Format.jobsAppsEyebrow, tint: Design.Label.secondary) {
            if model.claudeDesktopInstalled {
                AppRow(name: "Claude Desktop", fact: Format.claudeDesktopFact(model.claudeDesktopMCP)) {
                    if model.claudeDesktopMCP?.isConnected == true {
                        Button("Disconnect…", action: actions.disconnect).buttonStyle(AppButton(kind: .quiet))
                    } else if model.claudeDesktopMCP != nil {
                        Button("Connect", action: actions.connect).buttonStyle(AppButton(kind: .secondary))
                    }
                }
            }
            AppRow(name: "Terminal agents", fact: Format.terminalAgentsFact, last: true) {
                EmptyView()
            }
        }
    }

    /// The footer states; it configures nothing.
    private func footer(_ board: JobsBoard) -> some View {
        HStack(spacing: Win.s4) {
            Text(Format.jobsFooter(board)).font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: Win.s5)
        }
        .padding(.horizontal, Win.s6)
        .padding(.vertical, Win.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowSurface.hover)
        .overlay(alignment: .top) { Rectangle().fill(WindowSurface.separator).frame(height: 1) }
    }
}

/// A card that is an eyebrow over rows, with no title of its own: the
/// Grants window's card shape, for a list rather than one question.
struct JobsCard<Rows: View>: View {
    let eyebrow: String
    let tint: Color
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s4) {
            HStack(spacing: Win.s3) {
                StateDot(tint: tint)
                Text(eyebrow).font(Win.eyebrow).foregroundStyle(.secondary)
            }
            AppCardRows(content: rows)
        }
        .padding(Win.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
    }
}

struct AIJobsActions {
    var reload: () -> Void = {}
    var remove: (JobStatus) -> Void = { _ in }
    var newJob: () -> Void = {}
    var review: (JobProposal) -> Void = { _ in }
    var connect: () -> Void = {}
    var disconnect: () -> Void = {}
    var fit: (CGFloat) -> Void = { _ in }
}
