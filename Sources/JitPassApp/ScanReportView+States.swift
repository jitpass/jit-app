// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Findings window when it has no report: before the first scan,
/// while one runs, and after one failed. Each says what is true and offers the
/// one thing there is to do.
extension ScanReportView {
    /// Nothing is scanned until the user says where: a whole-home read is
    /// never a side effect of opening a window.
    var chooser: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            WindowEmptyState(
                tint: Color(StatusMark.amber),
                hollow: true,
                title: "No findings yet",
                message: ScanWording.emptyMessage(schedule: model.scanSchedule)
            ) {
                Button("Choose Folder…", action: actions.chooseFolder).buttonStyle(AppButton())
                Button("Scan Whole Mac…", action: actions.scanWholeMac).buttonStyle(AppButton(kind: .primary))
            }
            Spacer(minLength: 0)
            accessFooter
        }
    }

    var scanning: some View {
        VStack(spacing: 0) {
            header(nil)
            Spacer(minLength: 0)
            if model.scanDeep, !vaultUnlocked {
                // A deep scan reads the vault first. Locked, that is a
                // Touch ID prompt, and the window says what it is for.
                WindowEmptyState(
                    tint: Color(StatusMark.amber),
                    title: "Unlock the vault to search for your secrets",
                    message: "A deep scan compares your vaulted values against every file it reads. "
                        + "The values stay on this Mac and never appear in the results — only which secret was found, and where."
                ) {
                    EmptyView()
                }
            } else {
                VStack(spacing: Win.s5) {
                    ProgressView().controlSize(.small)
                    Text((model.scanDeep ? "Deep scan · " : "") +
                        (model.scanScope == nil ? "Reading your Mac…" : "Reading " + Format.home(model.scanScope ?? "") + "…"))
                        .font(Win.sub).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            accessFooter
        }
    }

    private var vaultUnlocked: Bool {
        if case .unlocked = model.state {
            return true
        }
        return false
    }

    func failed(_ error: String) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            WindowEmptyState(
                tint: Color(StatusMark.red),
                title: "The scan did not finish",
                message: error
            ) {
                Button("Try Again", action: actions.rescan).buttonStyle(AppButton(kind: .primary))
            }
            Spacer(minLength: 0)
            accessFooter
        }
    }

    /// Whether a whole-Mac scan will run quietly or raise a prompt per
    /// protected folder, in the one place that states it.
    var accessFooter: some View {
        HStack(spacing: Win.s4) {
            StateDot(tint: Color(model.fullDiskAccess ? StatusMark.green : StatusMark.amber))
            Text(
                model.fullDiskAccess
                    ? "Full Disk Access granted · scheduled scans run without prompts"
                    : "Without Full Disk Access, macOS asks once per protected folder"
            )
            .font(Win.sub).foregroundStyle(.secondary)
            Spacer(minLength: Win.s5)
            if !model.fullDiskAccess {
                Button("Grant Access…", action: actions.grantFullDiskAccess).buttonStyle(AppButton())
            }
        }
        .padding(.horizontal, Win.s6)
        .padding(.vertical, Win.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowSurface.hover)
        .overlay(alignment: .top) { Rectangle().fill(WindowSurface.separator).frame(height: 1) }
    }
}
