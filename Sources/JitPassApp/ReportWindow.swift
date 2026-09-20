// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import SwiftUI

/// An ordinary titled window for a report view. The app is otherwise a
/// menu bar item with no windows, so activation is explicit: the window is
/// brought to the front when shown and the app stays an accessory otherwise.
@MainActor
final class ReportWindow: NSWindow, NSWindowDelegate {
    /// Answers the close button; nil means always. The setup window says
    /// no while a Protect is moving secrets.
    var mayClose: (() -> Bool)?

    func windowShouldClose(_: NSWindow) -> Bool {
        mayClose?() ?? true
    }

    func windowWillClose(_: Notification) {
        userSized = false
    }

    init(title: String, content: some View, size: NSSize, minSize: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.title = title
        delegate = self
        isReleasedWhenClosed = false
        contentMinSize = minSize
        // The content draws its own translucent material; the window must
        // not paint an opaque background under it.
        isOpaque = false
        backgroundColor = .clear
        contentView = NSHostingView(rootView: content)
        setContentSize(size)
        center()
    }

    /// Set while the window itself is resizing its own frame, so the
    /// resize it causes is not read as the user's.
    private var fitting = false
    /// The user dragged an edge: the window is theirs now, and nothing
    /// resizes it again while it is open.
    private var userSized = false

    func windowDidResize(_: Notification) {
        if !fitting {
            userSized = true
        }
    }

    /// Opens at the height of what it holds, capped to the screen and
    /// never below its minimum, instead of a fixed height with nothing
    /// under the last card. Once the user has sized it, it is theirs;
    /// closing and opening again starts over.
    func fit(to height: CGFloat) {
        guard isVisible, !userSized, height > 0, let content = contentView else {
            return
        }
        let limit = (screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let wanted = min(max(height.rounded(.up), contentMinSize.height), limit * 0.9)
        guard abs(wanted - content.frame.height) > 1 else {
            return
        }
        // From the top edge: a window that grows from the bottom walks up
        // the screen every time a card appears.
        var wantedFrame = frameRect(forContentRect: NSRect(x: 0, y: 0, width: content.frame.width, height: wanted))
        wantedFrame.origin = NSPoint(x: frame.origin.x, y: frame.maxY - wantedFrame.height)
        fitting = true
        setFrame(wantedFrame, display: true)
        fitting = false
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// After a command that asked for Touch ID. The prompt is not ours, so
    /// when it closes macOS hands focus back to the app that had it before,
    /// and the next screen showed up inactive. Only a window still open
    /// comes back: one the user closed meanwhile stays closed.
    func reclaimFocus() {
        if isVisible {
            present()
        }
    }
}
