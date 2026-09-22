// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Decoys window: which files serve decoys, who read them and what
/// they got, which still hold plaintext, and which name a secret the vault
/// does not have. The panel row used to open the audit filtered to file
/// reads; nowhere listed the files. Built from the window system: header
/// with the Findings shape, cards by state, footer that states.
struct DecoysView: View {
    @ObservedObject var model: MenuModel
    let actions: DecoysActions

    var body: some View {
        let report = report()
        let open = model.macScan?.groups(in: .protect) ?? []
        VStack(spacing: 0) {
            // Its own banner: what a Protect started here did. Findings'
            // banner (a scheduled redact, a Protect from there) stays there.
            if let outcome = model.decoysOutcome {
                WindowBanner(tint: Color(outcome.failed ? StatusMark.red : StatusMark.green), text: outcome.title) {
                    if !outcome.text.isEmpty {
                        Button("What jit Did…") { actions.showOutcome(outcome) }.buttonStyle(AppButton(kind: .plain))
                    }
                }
            }
            header(report, open: open)
            if report.files.isEmpty, open.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Win.s5) {
                        if !report.broken.isEmpty {
                            brokenCard(report)
                        }
                        if !open.isEmpty {
                            openCard(open)
                        }
                        if !report.protected.isEmpty {
                            protectedCard(report)
                        }
                        if !report.reads.isEmpty {
                            readsCard(report)
                        }
                    }
                    .padding(Win.s6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            footer(report, open: open)
        }
        .frame(minWidth: Win.width, maxWidth: .infinity, minHeight: Win.minimum(Win.height), maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .sheet(item: $model.decoysSheet) { sheet in
            if case let .result(title, text) = sheet {
                ResultSheet(title: title, text: text, close: actions.closeSheet)
            }
        }
        .onAppear(perform: actions.reload)
    }

    private func report() -> DecoyReport {
        DecoyReport.make(
            mounts: model.cli?.protectedFiles ?? [],
            secrets: model.vaultListing?.secrets ?? [],
            events: model.decoyEvents,
            home: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    // MARK: - Header

    private func header(_ report: DecoyReport, open: [ScanFileGroup]) -> some View {
        HStack(alignment: .top, spacing: Win.s5) {
            WindowMark(tint: tint(report, open: open))
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(Format.decoysHeadline(report, open: open.count)).font(Win.head)
                let todos = todos(report, open: open)
                if !todos.isEmpty {
                    HeaderTodoLines(todos: todos).padding(.top, Win.s2)
                }
                Text(Format.decoysSubline(scanAt: model.macScanAt, deep: model.macScanKind?.isDeep == true))
                    .font(Win.sub).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, todos.isEmpty ? 0 : Win.s3)
            }
            Spacer(minLength: Win.s5)
            HStack(spacing: Win.s3) {
                if model.toolsBusy != nil {
                    ProgressView().controlSize(.small)
                }
                Button("Protect Another…", action: actions.protectAnother).buttonStyle(AppButton()).disabled(model.toolsBusy != nil)
                moreMenu
            }
            .padding(.top, Win.s1)
        }
        .windowRegion()
    }

    private func tint(_ report: DecoyReport, open: [ScanFileGroup]) -> Color {
        if !report.broken.isEmpty || !open.isEmpty {
            return Color(StatusMark.red)
        }
        return Color(report.decoyReads > 0 ? StatusMark.amber : StatusMark.green)
    }

    private func todos(_ report: DecoyReport, open: [ScanFileGroup]) -> [HeaderTodo] {
        var lines: [HeaderTodo] = []
        if !open.isEmpty {
            lines
                .append(HeaderTodo(id: "open", text: Format.decoysOpenLine(open.count), verb: "protect them", tint: Color(StatusMark.red)) {
                    actions.protectAll(ProtectPlan(migrate: open.map(\.filePath)))
                })
        }
        for file in report.broken {
            lines.append(HeaderTodo(
                id: "broken:" + file.path, text: Format.decoyFileName(file.path) + " names a secret the vault does not have",
                verb: "fix it", tint: Color(StatusMark.red), action: actions.openVault
            ))
        }
        if report.decoyReads > 0 {
            lines.append(HeaderTodo(
                id: "reads",
                text: Format.decoysReadsLine(report),
                verb: "see them",
                tint: Color(StatusMark.amber),
                action: actions.openAudit
            ))
        }
        return lines
    }

    private var moreMenu: some View {
        Menu {
            Button("Refresh", action: actions.reload)
            Divider()
            Button("Findings…", action: actions.openScan)
            Button("Vault…", action: actions.openVault)
            Button("Audit…", action: actions.openAudit)
        } label: {
            Text("···")
        }
        .menuStyle(.button)
        .buttonStyle(AppButton())
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Cards

    private func brokenCard(_ report: DecoyReport) -> some View {
        AppCard(
            eyebrow: "Fix now", eyebrowTint: Color(StatusMark.red),
            title: Format
                .count(report.broken.count, "file") + (report.broken.count == 1 ? " names" : " name") + " a secret the vault does not have",
            note: "A run asked for it and got nothing. Put the value in the vault, or take the name out of the file."
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                ForEach(Array(report.broken.enumerated()), id: \.element.id) { index, file in
                    fileRow(file, last: index == report.broken.count - 1)
                }
            }
        }
    }

    private func openCard(_ groups: [ScanFileGroup]) -> some View {
        AppCard(
            eyebrow: "In the open", eyebrowTint: Color(StatusMark.red),
            title: Format.count(groups.count, "file") + (groups.count == 1 ? " holds" : " hold") + " plaintext secrets",
            note: Format.decoysOpenNote
        ) {
            if groups.count > 1 {
                Button("Protect All \(groups.count)…") { actions.protectAll(ProtectPlan(migrate: groups.map(\.filePath))) }
                    .buttonStyle(AppButton(kind: .secondary)).disabled(model.toolsBusy != nil)
            }
        } rows: {
            AppCardRows {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    AppRow(
                        name: Format.fileName(group.filePath),
                        detail: Format.parentFolder(group.filePath),
                        fact: group.fact,
                        last: index == groups.count - 1
                    ) {
                        Button("Open") { actions.open(group.filePath, group.firstLine) }.buttonStyle(AppButton())
                        if let finding = group.findings.first(where: { $0.fixCommand != nil }) {
                            Button("Protect…") { actions.protect(finding) }.buttonStyle(AppButton(kind: .secondary))
                                .disabled(model.toolsBusy != nil)
                        }
                    }
                }
            }
        }
    }

    private func protectedCard(_ report: DecoyReport) -> some View {
        AppCard(
            eyebrow: "Protected", eyebrowTint: Color(StatusMark.green),
            title: Format.count(report.protected.count, "file") + (report.protected.count == 1 ? " serves" : " serve") + " decoys",
            note: Format.decoysProtectedNote
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                ForEach(Array(report.protected.enumerated()), id: \.element.id) { index, file in
                    fileRow(file, last: index == report.protected.count - 1)
                }
            }
        }
    }

    private func fileRow(_ file: DecoyReport.File, last: Bool) -> some View {
        AppRow(name: Format.decoyFileName(file.path), detail: Format.decoyFolder(file.path), fact: Format.decoyFileFact(file), last: last) {
            // A protected file is a pipe: an editor cannot open it, and
            // reading it would itself be a decoy read. Finder only.
            Button("Show in Finder") { actions.reveal(file.path) }.buttonStyle(AppButton())
            Button("Vault…", action: actions.openVault).buttonStyle(AppButton())
        }
    }

    private func readsCard(_ report: DecoyReport) -> some View {
        AppCard(
            eyebrow: "Reads", eyebrowTint: Color(report.decoyReads > 0 ? StatusMark.amber : StatusMark.green),
            title: Format.count(report.decoyReads, "decoy read") + " in 7 days · " + Format.count(
                report.realReads,
                "real read",
                plural: "real reads"
            ),
            note: Format.decoysReadsNote
        ) {
            Button("Audit…", action: actions.openAudit).buttonStyle(AppButton(kind: .plain))
        } rows: {
            AppCardRows {
                ForEach(Array(report.reads.prefix(12).enumerated()), id: \.element.id) { index, read in
                    AppRow(
                        name: ScanWording.when(read.at),
                        detail: Format.decoyReadFiles(read),
                        fact: Format.decoyReadFact(read),
                        last: index == min(report.reads.count, 12) - 1
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            WindowEmptyState(
                tint: Color(StatusMark.green), hollow: true,
                title: "No file is protected yet",
                message: Format.decoysEmptyMessage
            ) {
                Button("Findings…", action: actions.openScan).buttonStyle(AppButton())
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer

    private func footer(_ report: DecoyReport, open: [ScanFileGroup]) -> some View {
        HStack(spacing: Win.s4) {
            StateDot(tint: tint(report, open: open))
            Text(Format.decoysFooter(report, open: open.count)).font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: Win.s5)
        }
        .padding(.horizontal, Win.s6)
        .padding(.vertical, Win.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowSurface.hover)
        .overlay(alignment: .top) { Rectangle().fill(WindowSurface.separator).frame(height: 1) }
    }
}

struct DecoysActions {
    var reload: () -> Void = {}
    var closeSheet: () -> Void = {}
    var showOutcome: (WindowOutcome) -> Void = { _ in }
    var open: (String, Int?) -> Void = { _, _ in }
    var reveal: (String) -> Void = { _ in }
    var openVault: () -> Void = {}
    var openScan: () -> Void = {}
    var openAudit: () -> Void = {}
    var protect: (ScanFinding) -> Void = { _ in }
    var protectAll: (ProtectPlan) -> Void = { _ in }
    /// A file picker, then jit migrate on the file: the Protect verb for a
    /// file the scan did not list.
    var protectAnother: () -> Void = {}
}
