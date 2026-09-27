// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import SwiftUI

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

/// A question drawn in SwiftUI, asked as its own modal window: for one that
/// belongs to no single window's sheet (Protect is asked from Findings and
/// from Decoys). Brought forward first, as every dialog here is. `make`
/// gets the finish call; true is the question's yes, handed to `then`.
///
/// Asked on the run loop's next turn, never inside the caller: a modal
/// loop started from a SwiftUI button's action leaves the panel's own
/// SwiftUI buttons and keyboard shortcuts dead — the dialog cannot be
/// answered and the app has to be killed (the Protect sheet in 2.3.1).
/// An NSAlert there is fine, its buttons are AppKit's.
enum ModalHost {
    @MainActor
    static func ask(
        title: String,
        _ make: @escaping (_ finish: @escaping (Bool) -> Void) -> some View,
        then: @escaping @MainActor (Bool) -> Void
    ) {
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated {
                then(run(title: title, make))
            }
        }
    }

    @MainActor
    private static func run(title: String, _ make: (_ finish: @escaping (Bool) -> Void) -> some View) -> Bool {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        var answer = false
        let finish: (Bool) -> Void = { yes in
            answer = yes
            NSApp.stopModal()
        }
        panel.contentView = NSHostingView(rootView: make(finish))
        panel.setContentSize(panel.contentView?.fittingSize ?? .zero)
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return answer
    }
}
