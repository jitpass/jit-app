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
}
