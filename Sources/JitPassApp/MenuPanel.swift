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
    /// The panel opened itself for a request shown beside its Touch ID. It
    /// then took no focus, closes no matter where the human clicks (the
    /// Touch ID dialog, "Use Password…"), and is the only kind that closes
    /// itself after the answer. A panel the human opened stays theirs.
    private(set) var openedForConsent = false

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
        guard place(under: button) else {
            return
        }
        openedForConsent = false
        makeKeyAndOrderFront(nil)
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    /// Opens the panel for a request shown beside its Touch ID, without
    /// taking focus: the Touch ID stays the one thing to answer, and a click
    /// on Deny still reaches the panel (the spike, jitpass/jit#197). Already
    /// open, it only grows to fit the request.
    func showBeside(under button: NSStatusBarButton) {
        if isVisible {
            refit()
            return
        }
        guard place(under: button) else {
            return
        }
        openedForConsent = true
        orderFrontRegardless()
    }

    /// Resizes to the content, keeping the top right corner under the status
    /// item: the Asking block arriving or leaving changes the height.
    func refit() {
        guard isVisible else {
            return
        }
        layoutIfNeeded()
        let size = contentView?.fittingSize ?? .zero
        let origin = NSPoint(x: frame.maxX - size.width, y: frame.maxY - size.height)
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func place(under button: NSStatusBarButton) -> Bool {
        guard let buttonWindow = button.window else {
            return false
        }
        layoutIfNeeded()
        let size = contentView?.fittingSize ?? .zero
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let origin = NSPoint(x: anchor.maxX - size.width, y: anchor.minY - size.height - 6)
        setFrame(NSRect(origin: origin, size: size), display: true)
        return true
    }

    func dismiss() {
        openedForConsent = false
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
        // A click on Deny makes the panel key; answering the Touch ID
        // afterwards must not take the answer's line away with it.
        if !openedForConsent {
            dismiss()
        }
    }
}
