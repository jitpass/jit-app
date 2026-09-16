// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import SwiftUI

/// A borderless, non-activating panel hung under the status item, closed by
/// a click anywhere else or Escape. NSMenu cannot draw the mockup's header
/// and icon rows, so the dropdown is a window that behaves like a menu.
@MainActor
final class MenuPanel: NSPanel {
    private var outsideClick: Any?

    init(content: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: content)
        contentView?.wantsLayer = true
    }

    override var canBecomeKey: Bool {
        true
    }

    func toggle(under button: NSStatusBarButton) {
        if isVisible {
            dismiss()
        } else {
            show(under: button)
        }
    }

    private func show(under button: NSStatusBarButton) {
        guard let buttonWindow = button.window else {
            return
        }
        layoutIfNeeded()
        let size = contentView?.fittingSize ?? .zero
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let origin = NSPoint(x: anchor.maxX - size.width, y: anchor.minY - size.height - 6)
        setFrame(NSRect(origin: origin, size: size), display: true)
        makeKeyAndOrderFront(nil)
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func dismiss() {
        if let outsideClick {
            NSEvent.removeMonitor(outsideClick)
            self.outsideClick = nil
        }
        orderOut(nil)
    }

    override func cancelOperation(_: Any?) {
        dismiss()
    }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }
}
