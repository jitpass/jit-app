// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// The jitpass mark: a dot inside a soft ring (jitpass.com/icon.svg). The dot
/// colour carries state, matching the terminal palette: green healthy, red a
/// state the user must act on, amber a question.
enum StatusMark {
    static let green = NSColor(srgbRed: 0x3E / 255, green: 0xCF / 255, blue: 0x8E / 255, alpha: 1)
    static let red = NSColor(srgbRed: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255, alpha: 1)
    static let amber = NSColor(srgbRed: 0xF0 / 255, green: 0xB5 / 255, blue: 0x45 / 255, alpha: 1)
    /// The one colour for the one thing you can act on, matching the
    /// terminal's cyan role.
    static let accent = NSColor(srgbRed: 0x7F / 255, green: 0xD4 / 255, blue: 0xFF / 255, alpha: 1)

    static func color(for state: SessionState) -> NSColor {
        switch state {
        case .unlocked: green
        case .locked, .notRunning: red
        }
    }

    static func pillTitle(for state: SessionState) -> String {
        switch state {
        case .unlocked: "OK"
        case .locked: "Locked"
        case .notRunning: "Off"
        }
    }

    static func image(for state: SessionState, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let tint = color(for: state)
            tint.withAlphaComponent(0.22).setFill()
            NSBezierPath(ovalIn: rect).fill()
            tint.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: size * 0.22, dy: size * 0.22)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
