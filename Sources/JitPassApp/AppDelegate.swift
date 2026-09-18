// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_: Notification) {
        guard Translocation.warnIfNeeded() else {
            NSApp.terminate(nil)
            return
        }
        statusItem = StatusItemController(client: AgentClient())
        statusItem?.start()
    }

    /// Opening the app again is what someone does when nothing seemed to
    /// happen: an accessory app has no Dock icon and no window, and on a
    /// full menu bar macOS can hide the ring behind the notch. It brings
    /// setup forward for a Mac with no vault, and the panel otherwise.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        statusItem?.reopened()
        return false
    }

    /// A Protect in flight is moving secrets and rewriting files. Every
    /// file it touches has a backup, but a quit half way is still worth a
    /// question.
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard statusItem?.onboarding.protecting == true else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Setup is moving secrets"
        alert.informativeText = "Quitting now leaves it half done. Nothing is lost: every file has an encrypted backup, "
            + "and setup picks up where it stopped."
        alert.addButton(withTitle: "Keep Going")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
}
