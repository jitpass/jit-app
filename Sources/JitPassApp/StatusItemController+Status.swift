// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// The session status the panel and the menu bar mark show: the agent's
/// word every second while the panel is open, and `jit status` off the
/// main thread.
extension StatusItemController {
    /// The countdown on screen needs a read every second. With the panel
    /// closed, the stream says when the state changes (it re-polls on every
    /// event) and this is only the fallback.
    func tickStatus() {
        guard panel.isVisible || Date().timeIntervalSince(lastPoll) >= Self.idlePollInterval else {
            return
        }
        pollStatus()
    }

    static let idlePollInterval: TimeInterval = 5

    func pollStatus() {
        lastPoll = Date()
        var changed = false
        do {
            let status = try client.status()
            changed = model.set(\.state, SessionState(response: status))
            changed = model.set(\.consentEnabled, status.consentEnabled) || changed
            changed = model.set(\.ttlSeconds, status.ttlSeconds) || changed
            changed = model.set(\.serviceExecutable, status.executablePath) || changed
        } catch AgentClientError.notRunning {
            changed = model.set(\.state, .notRunning)
            changed = model.set(\.grants, []) || changed
        } catch {
            // Keep the last known state on a transient error; the next tick retries.
        }
        if changed {
            render()
        }
    }

    /// `jit status` off the main thread: each run is a process spawn the
    /// window should not wait on. The menu bar mark reads the result.
    /// `fresh` false takes the cached status when it is recent.
    func refreshCLI(fresh: Bool = true) {
        Task.detached {
            if fresh {
                JitCLI.forgetStatus()
            }
            let status = JitCLI.status()
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.cli = status
                render()
            }
        }
    }
}
