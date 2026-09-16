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
            run: { [weak self] command in self?.runInTerminal(command) }
        )
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
