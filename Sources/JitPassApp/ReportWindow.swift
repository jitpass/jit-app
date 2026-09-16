// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import SwiftUI

/// An ordinary titled window for a report view. The app is otherwise a
/// menu bar item with no windows, so activation is explicit: the window is
/// brought to the front when shown and the app stays an accessory otherwise.
@MainActor
final class ReportWindow: NSWindow {
    init(title: String, content: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.title = title
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: content)
        setContentSize(contentView?.fittingSize ?? .zero)
        center()
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
