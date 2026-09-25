// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import SwiftUI

/// The JitPass design system, as the app can use it.
///
/// The source of truth is the design system artifact, section **Windows**,
/// and its `project/tokens.json`. Every number here is a token from there;
/// nothing in this file is a judgement call. If a view needs a value that
/// is not here, the value is missing from the system: add it there first,
/// then here, and never pick one in the view.
///
/// State colour is not in this file. It lives in `StatusMark` and only
/// there, so the menu bar mark, the panel dots and a window's rows can
/// never disagree about what green means.
enum Design {
    // MARK: - Spacing

    /// The six steps. Every gap and every padding inside an app window is
    /// one of them; 9, 10, 11, 14 and 16 round to the nearest step.
    enum Space {
        /// 2pt. The two lines of a row or a header.
        static let one: CGFloat = 2
        /// 4pt. Two controls that are one control.
        static let two: CGFloat = 4
        /// 6pt. Buttons in a row's action group; a dot and its word.
        static let three: CGFloat = 6
        /// 8pt. Buttons in a footer or sheet; a row's vertical padding.
        static let four: CGFloat = 8
        /// 12pt. Between cards; a header's and toolbar's vertical padding.
        static let five: CGFloat = 12
        /// 18pt. The window inset, and a sheet's padding. The only value
        /// that touches an edge.
        static let six: CGFloat = 18
    }

    // MARK: - Type

    /// Every size in an app window, and nothing else. Three weights:
    /// regular for facts, semibold for names, bold for a setup headline.
    enum Text {
        /// 15 semibold. The window's own headline.
        static let windowHead = Font.system(size: 15, weight: .semibold)
        /// 12 regular. The sentence under it, in `Label.secondary`.
        static let windowSub = Font.system(size: 12)
        /// 11 medium. A card's tier label, beside its dot.
        static let eyebrow = Font.system(size: 11, weight: .medium)
        /// 13 semibold. A card's title.
        static let cardTitle = Font.system(size: 13, weight: .semibold)
        /// 12 regular. A card's explanation. Cap it at 62 characters wide.
        static let cardNote = Font.system(size: 12)
        /// 13 semibold. A row's first line: the thing itself.
        static let rowName = Font.system(size: 13, weight: .semibold)
        /// 11 regular. A row's second line: the one fact that decides it.
        static let rowFact = Font.system(size: 11)
        /// 12 regular. Every button inside a window, sheet or alert.
        static let button = Font.system(size: 12)
        /// 14 semibold. An empty state's headline.
        static let emptyTitle = Font.system(size: 14, weight: .semibold)
        /// 13 regular. Panel rows, sheet body.
        static let row = Font.system(size: 13)
        /// 12 monospaced. A command, a path, a key name, a verbatim line.
        static let command = Font.system(size: 12, design: .monospaced)
        /// 11 monospaced. The folder that tells two rows apart, and the
        /// block carrying jit's own words after a failure.
        static let commandSmall = Font.system(size: 11, design: .monospaced)
    }

    // MARK: - Radius

    enum Radius {
        /// 4pt. A checkbox, and the chip behind a key name.
        static let box: CGFloat = 4
        /// 5pt. The selected pill inside a segmented filter.
        static let segment: CGFloat = 5
        /// 6pt. Buttons, search fields, the verbatim block.
        static let control: CGFloat = 6
        /// 7pt. A segmented filter's track.
        static let callout: CGFloat = 7
        /// 10pt. Cards, and the menu bar panel.
        static let panel: CGFloat = 10
        /// 12pt. An alert.
        static let card: CGFloat = 12
    }

    // MARK: - Window sizes

    /// Three widths, no fourth. A window that fits none of them is asking
    /// the wrong question: split it, or drop a column.
    ///
    /// A window opens at the height below and grows with its content. It
    /// never opens at a fixed height that ends in empty space.
    enum Window {
        /// 520 x 400. One purpose, nothing to filter.
        static let small = NSSize(width: 520, height: 400)
        /// 720 x 480. The default report window.
        static let medium = NSSize(width: 720, height: 480)
        /// 900 x 560. Two panes, or rows with three columns and actions.
        static let large = NSSize(width: 900, height: 560)
        /// 620 x 540, fixed. Setup and offboarding: a flow with a page
        /// count cannot reflow.
        static let flow = NSSize(width: 620, height: 540)

        /// The floor for a window: its width, and two thirds of its
        /// opening height. Below that, hide the toolbar before you let a
        /// row wrap.
        static func minimum(for size: NSSize) -> NSSize {
            NSSize(width: size.width, height: (size.height * 2 / 3).rounded())
        }
    }

    /// 500 the consent sheet, 520 any sheet whose content includes a path
    /// (it must not wrap mid-word), 440 an alert. A question needing more
    /// than 440 is a sheet; one needing a scroll is a window.
    enum Sheet {
        static let consent: CGFloat = 500
        static let wide: CGFloat = 520
        static let alert: CGFloat = 440
    }

    /// Control heights.
    enum Size {
        /// 22pt. A button inside a window, a card or a row.
        static let button: CGFloat = 22
        /// 30pt. A button in a setup footer, where it is the one action.
        static let buttonLarge: CGFloat = 30
        /// 8pt. A state dot. Never alone: at this size `StatusMark.red` on
        /// the window material is 2.3:1, so every dot has its word.
        static let dot: CGFloat = 8
        /// 16pt. An outcome glyph, and a row's leading icon.
        static let glyph: CGFloat = 16
        /// 34pt. The status mark in a window header or the panel.
        static let mark: CGFloat = 34
        /// 56pt. The status mark in an empty state.
        static let markLarge: CGFloat = 56
        /// 62 characters. The cap on a card's note: past that the eye
        /// loses the line.
        static let noteWidth = 62
    }

    // MARK: - Surfaces

    /// App windows draw a translucent material, so every surface above it
    /// is an overlay, not an opaque fill. The hex values in `tokens.json`
    /// (`app-window` #323438, `app-card` #414347) are samples for static
    /// mockups; painting them here would stop the window tinting with the
    /// wallpaper behind it.
    enum Surface {
        /// A card on the window material. The overlay equivalent of the
        /// sampled `app-card`.
        static let card = Color.white.opacity(0.07)
        /// Between a window's regions.
        static let separator = Color.white.opacity(0.10)
        /// Between rows inside a card. One step quieter than `separator`.
        static let rowLine = Color.white.opacity(0.07)
        /// A row under the pointer.
        static let hover = Color.white.opacity(0.05)
        /// A search or text field, and the chip behind a key name.
        static let field = Color.white.opacity(0.07)
        /// The border of a secondary button, a field, a checkbox.
        static let controlLine = Color.white.opacity(0.16)
        /// A quiet button: a low-stakes action inside a row or card.
        static let buttonQuiet = Color.white.opacity(0.13)
        /// The track a segmented filter's pills sit in.
        static let segmentTrack = Color.white.opacity(0.08)
        /// The selected pill of a segmented filter.
        static let segmentOn = Color.white.opacity(0.16)
        /// The block carrying jit's own words after a failure. The app's
        /// replacement for a terminal pane, and the only place raw output
        /// belongs on screen.
        static let verbatim = Color.black.opacity(0.20)
    }

    /// macOS label greys on a dark material.
    enum Label {
        /// Headlines, row names, values.
        static let primary = Color.white.opacity(0.85)
        /// Detail lines, facts, field labels, footnotes.
        static let secondary = Color.white.opacity(0.55)
        /// Shortcut hints and trailing counts. Decorative, never
        /// information: it does not meet 4.5:1.
        static let tertiary = Color.white.opacity(0.25)
    }

    /// Opacities that are rules of a control, not surfaces.
    enum Opacity {
        /// 45%. A disabled button, which keeps its label (windows.md,
        /// Controls: "A disabled button is 45% opacity"). Not yet a named
        /// token in the artifact's `tokens.json`.
        static let disabled = 0.45
    }

    /// The macOS accent for default buttons, switches that are on, and a
    /// checked checkbox. A control takes the system accent, never the
    /// brand green: green is the mark, a healthy state and a filled
    /// progress bar. The real app follows the user's own accent.
    static let controlAccent = Color.accentColor

    // MARK: - Motion

    /// 140ms on colour, border and background. No entrance animations, no
    /// sliding rows. A pressed button drops 1pt.
    static let transition = Animation.easeInOut(duration: 0.14)
}
