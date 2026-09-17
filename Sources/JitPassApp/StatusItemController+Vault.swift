// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient
import os

/// Never a value: bytes counts and which hide path fired.
private let vaultLog = Logger(subsystem: "com.jitpass.app", category: "vault")

/// The Vault window: `jit vault` as rows, sheets and dialogs. The rules are
/// in docs/design/vault-window.md §5: a value appears only in the Reveal
/// field after its own Touch ID; `--yes` is passed only after a dialog
/// here has asked the same question; values reach jit through stdin.
extension StatusItemController {
    /// How long a revealed value stays on screen.
    static let revealSeconds = 10

    var vaultActions: VaultActions {
        VaultActions(
            reload: { [weak self] in self?.reloadVault() },
            openSheet: { [weak self] sheet in
                self?.model.vaultMessage = nil
                self?.model.vaultSheet = sheet
            },
            closeSheet: { [weak self] in
                self?.model.vaultSheet = nil
                self?.model.vaultMessage = nil
            },
            reveal: { [weak self] path in self?.reveal(path) },
            hideReveal: { [weak self] in self?.hideReveal() },
            copy: { [weak self] path in self?.copySecret(path) },
            set: { [weak self] path, value, replacing in self?.setSecret(path, value: value, replacing: replacing) },
            link: { [weak self] path, reference, verify, replacing in
                self?.linkSecret(path, reference: reference, verify: verify, replacing: replacing)
            },
            loadHistory: { [weak self] path in self?.loadHistory(path) },
            restore: { [weak self] path, stamp in self?.restoreSecret(path, stamp: stamp) },
            delete: { [weak self] paths in self?.deleteSecrets(paths) },
            openInTerminal: { [weak self] in self?.runInTerminal("jit vault list -l") },
            loadOrphans: { [weak self] in self?.loadOrphans() },
            pruneOrphans: { [weak self] in self?.pruneOrphans() },
            pruneBackups: { [weak self] in self?.pruneBackups() },
            exportVault: { [weak self] in self?.exportVault() },
            importVault: { [weak self] in self?.importVault() },
            rekey: { [weak self] in self?.rekeyVault() },
            compareDuplicates: { [weak self] in self?.compareDuplicates() },
            pruneDuplicates: { [weak self] in self?.pruneDuplicates() }
        )
    }

    func openVault() {
        panel.dismiss()
        installVaultObservers()
        reloadVault()
        vaultWindow.present()
    }

    /// Prompt-free, so it runs after every operation and on every open.
    func reloadVault() {
        do {
            model.vaultListing = try JitCLI.vaultList()
        } catch {
            model.vaultMessage = Format.error(error)
        }
    }

    // MARK: - Reveal

    /// `jit vault get` after its own Touch ID; the bytes land in one
    /// `SecretBuffer`, the row shows them for `revealSeconds`, then every
    /// hide path (timer, Hide, window close, app deactivation, screen lock,
    /// the panel opening) wipes the buffer and drops the String.
    func reveal(_ path: String) {
        hideReveal(reason: "new reveal")
        vaultLog.notice("reveal start \(path, privacy: .public)")
        runVault(path, refresh: false, work: { JitCLI.reveal(path) }, then: { [weak self] buffer in
            guard let self else {
                buffer.wipe()
                return
            }
            let active = NSApp.isActive
            vaultLog.notice("reveal got \(buffer.count) bytes for \(path, privacy: .public); active=\(active)")
            revealBuffer = buffer
            model.vaultReveal = VaultReveal(path: path, text: buffer.text, secondsLeft: Self.revealSeconds)
            revealTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.revealTick() }
            }
        })
    }

    private func revealTick() {
        guard var reveal = model.vaultReveal else {
            hideReveal()
            return
        }
        reveal.secondsLeft -= 1
        if reveal.secondsLeft <= 0 {
            hideReveal(reason: "timer")
        } else {
            model.vaultReveal = reveal
        }
    }

    func hideReveal(reason: String = "click") {
        if model.vaultReveal != nil || revealBuffer != nil {
            vaultLog.notice("hide reveal: \(reason, privacy: .public)")
        }
        revealTimer?.invalidate()
        revealTimer = nil
        revealBuffer?.wipe()
        revealBuffer = nil
        if model.vaultReveal != nil {
            model.vaultReveal = nil
        }
    }

    /// Set up once: the hide paths that are not a click in the window.
    private func installVaultObservers() {
        guard vaultObservers.isEmpty else {
            return
        }
        let center = NotificationCenter.default
        vaultObservers
            .append(center.addObserver(forName: NSWindow.willCloseNotification, object: vaultWindow, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.hideReveal() }
            })
        vaultObservers
            .append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.hideReveal(reason: "app resigned active") }
            })
        vaultObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hideReveal(reason: "screen locked") }
        })
    }

    // MARK: - Operations

    /// `jit vault get --copy`: jit writes the pasteboard itself, concealed
    /// from clipboard managers and cleared after 45 seconds. The app reads
    /// its one confirmation line, never the value.
    private func copySecret(_ path: String) {
        hideReveal()
        runVault(path, work: { JitCLI.execute(["vault", "get", path, "--copy"]) }, then: { [weak self] output in
            let line = output.split(separator: "\n").last.map(String.init) ?? "Copied"
            let copied = line.hasPrefix("Copied to clipboard, clears in")
            self?.notice(copied ? "Copied · clears in 45s unless something else is copied first" : line)
        })
    }

    private func setSecret(_ path: String, value: String, replacing: Bool) {
        let arguments = ["vault", "set", path, "--stdin"] + (replacing ? ["--yes"] : [])
        runVault(path, work: { JitCLI.execute(arguments, stdin: value) }, then: { [weak self] _ in
            self?.model.vaultSheet = nil
            self?.notice(replacing ? "\(path) replaced · the previous value is in its history" : "\(path) stored")
        })
    }

    private func linkSecret(_ path: String, reference: String, verify: Bool, replacing: Bool) {
        let arguments = ["vault", "link", path, reference] + (verify ? [] : ["--no-verify"]) + (replacing ? ["--yes"] : [])
        runVault(path, work: { JitCLI.execute(arguments) }, then: { [weak self] _ in
            self?.model.vaultSheet = nil
            self?.notice("\(path) linked to 1Password")
        })
    }

    private func loadHistory(_ path: String) {
        model.vaultHistory = nil
        do {
            model.vaultHistory = try JitCLI.vaultHistory(path)
        } catch {
            model.vaultMessage = Format.error(error)
        }
    }

    private func restoreSecret(_ path: String, stamp: Int64) {
        let alert = NSAlert()
        alert.messageText = "Restore \(path)?"
        let archived = Format.ago(Date(timeIntervalSince1970: TimeInterval(stamp)))
        alert.informativeText = "The value archived \(archived) becomes current. "
            + "The current value is archived first, so this is reversible. Touch ID follows."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        runVault(path, work: { JitCLI.execute(["vault", "restore", path, "--version", String(stamp)]) }, then: { [weak self] _ in
            self?.model.vaultSheet = nil
            self?.notice("\(path) restored")
        })
    }

    /// One dialog listing exactly the paths that run, then `rm --yes`: the
    /// CLI's own y/N cannot be answered from here, so this is the only
    /// question, and it says so.
    private func deleteSecrets(_ paths: [String]) {
        guard let first = paths.first else {
            return
        }
        let alert = NSAlert()
        alert.messageText = paths.count == 1 ? "Delete \(first)?" : "Delete \(paths.count) secrets?"
        alert.informativeText = "This runs:\n\njit vault rm " + paths.joined(separator: " ")
            + "\n\nIt deletes " + (paths.count == 1 ? "the secret" : "every one of them")
            + " and its history for good, and nothing asks again."
            + usedByWarning(paths)
            + " Touch ID follows."
        alert.alertStyle = .warning
        alert.addButton(withTitle: paths.count == 1 ? "Delete" : "Delete \(paths.count)")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        hideReveal()
        let label = paths.count == 1 ? first : "\(paths.count) secrets"
        runVault(label, work: { JitCLI.execute(["vault", "rm"] + paths + ["--yes"]) }, then: { [weak self] _ in
            self?.model.scanStale = true
            self?.notice(paths.count == 1 ? "\(first) deleted" : "\(paths.count) secrets deleted")
        })
    }

    /// The profiles still pointing at what is about to go, from the
    /// listing's `used_by`: a wrap or a mount that keeps naming a deleted
    /// path serves nothing, and the right move there is unwrap or
    /// `jit migrate remove`, not `rm`.
    private func usedByWarning(_ paths: [String]) -> String {
        let secrets = (model.vaultListing?.secrets ?? []).filter { paths.contains($0.path) && !$0.usedBy.isEmpty }
        guard !secrets.isEmpty else {
            return ""
        }
        let profiles = Array(Set(secrets.flatMap(\.usedBy))).sorted()
        let names = profiles.joined(separator: ", ")
        return "\n\nStill used by \(profiles.count == 1 ? "profile" : "profiles") \(names): "
            + "whatever reads through \(profiles.count == 1 ? "it" : "them") gets nothing afterwards. "
            + "Unwrap the tool or jit migrate remove the file instead if that is not what you want."
    }

    // MARK: - Plumbing

    /// Runs one vault command off the main thread while the row and the
    /// header show who is waiting on Touch ID, then reloads the listing.
    /// One at a time: two Touch ID prompts at once is a mess.
    func runVault<T: Sendable>(
        _ label: String,
        refresh: Bool = true,
        work: @escaping @Sendable () -> Result<T, Error>,
        then: @escaping @MainActor (T) -> Void
    ) {
        guard model.vaultBusy == nil else {
            return
        }
        model.vaultBusy = label
        model.vaultMessage = nil
        model.vaultNotice = nil
        Task.detached {
            let result = work()
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                model.vaultBusy = nil
                switch result {
                case let .success(value):
                    then(value)
                    if refresh {
                        reloadVault()
                        JitCLI.forgetStatus()
                        model.cli = JitCLI.status()
                    }
                case let .failure(error):
                    vaultLog.error("vault op failed for \(label, privacy: .public): \(Self.describeVault(error), privacy: .public)")
                    model.vaultMessage = Self.describeVault(error)
                }
            }
        }
    }

    private nonisolated static func describeVault(_ error: Error) -> String {
        if case let JitCLI.CLIError.failed(line) = error {
            return line.isEmpty ? "jit did not say why" : line
        }
        if case JitCLI.CLIError.notInstalled = error {
            return "jit is not installed"
        }
        return Format.error(error)
    }

    func notice(_ text: String) {
        model.vaultNotice = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if self?.model.vaultNotice == text {
                self?.model.vaultNotice = nil
            }
        }
    }
}
