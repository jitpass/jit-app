// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Doctor: the panel row and the findings window.
extension StatusItemController {
    var doctorActions: DoctorActions {
        DoctorActions(
            recheck: { [weak self] in self?.runDoctor() },
            openInTerminal: { [weak self] in self?.runInTerminal("jit doctor") },
            run: { [weak self] command in self?.runInTerminal(command) },
            deleteProfile: { [weak self] name in self?.confirmDeleteProfile(name) }
        )
    }

    /// The one destructive act the app performs itself, and it is a move
    /// to the Trash of a manifest that holds no secret. Confirmed first,
    /// named exactly, and followed by a recheck so the row disappears
    /// because doctor says so, not because the app assumed.
    private func confirmDeleteProfile(_ name: String) {
        let alert = NSAlert()
        alert.messageText = "Delete the profile \u{201C}\(name)\u{201D}?"
        alert.informativeText = "Moves \(Format.home(ProfileStore.manifest(named: name).path)) to the Trash. "
            + "Anything that launched through this profile stops receiving its secrets. The vault is not changed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        do {
            try ProfileStore.trashGlobal(named: name)
        } catch {
            let failed = NSAlert(error: error)
            failed.runModal()
        }
        runDoctor()
    }

    func openDoctor() {
        panel.dismiss()
        doctorWindow.present()
        if model.doctor == nil {
            runDoctor()
        }
    }

    /// `jit doctor` is prompt-free (it checks envelopes without decrypting)
    /// and takes well under a second, so it runs on every panel open as
    /// well as on demand; off the main thread either way.
    func runDoctor() {
        guard !model.doctorRunning else {
            return
        }
        model.doctorRunning = true
        Task.detached {
            let report = JitCLI.doctor()
            await MainActor.run { [weak self] in
                self?.model.doctor = report
                self?.model.doctorRunning = false
            }
        }
    }
}
