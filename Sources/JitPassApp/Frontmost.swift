// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit

// Every alert and file panel the app shows opens through `runFrontmost`.
// JitPass is an accessory app, so it is usually not the active app when one
// opens, and a modal window of an inactive app takes neither the keyboard nor
// its default button until it is clicked: the passphrase dialog came up with
// a grey Save. `ModalDialogTests` fails on a bare `runModal()` anywhere else.

extension NSAlert {
    @MainActor @discardableResult
    func runFrontmost() -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return runModal()
    }
}

extension NSSavePanel {
    /// NSOpenPanel too: it is a save panel subclass.
    @MainActor @discardableResult
    func runFrontmost() -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return runModal()
    }
}
