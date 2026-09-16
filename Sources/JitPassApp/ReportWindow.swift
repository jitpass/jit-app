// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import SwiftUI

/// An ordinary titled window for a report view. The app is otherwise a
/// menu bar item with no windows, so activation is explicit: the window is
/// brought to the front when shown and the app stays an accessory otherwise.
@MainActor
final class ReportWindow: NSWindow {
    init(title: String, content: some View, size: NSSize, minSize: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.title = title
        isReleasedWhenClosed = false
        contentMinSize = minSize
        contentView = NSHostingView(rootView: content)
        setContentSize(size)
        center()
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
