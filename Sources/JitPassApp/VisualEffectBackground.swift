// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import SwiftUI

/// The system's own translucent material, the one real menus are drawn on,
/// so the panel takes the wallpaper tint and the light or dark appearance
/// exactly as an NSMenu would.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var cornerRadius: CGFloat = 10

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        view.material = material
        view.layer?.cornerRadius = cornerRadius
    }
}
