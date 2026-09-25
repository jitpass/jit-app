// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import SwiftUI

/// The window system from the design system's `windows.md`: a window is a
/// stack of regions at one inset, holding cards, holding rows, and nothing
/// else nests. Every number a window view uses is here, so a view never
/// picks one: if a value is missing it belongs in this file and in
/// `windows.md`, not in the view.
enum Win {
    /// Spacing. Six steps, and every gap and padding is one of them.
    /// The two lines of a row or a header.
    static let s1: CGFloat = 2
    /// Two controls that are one control.
    static let s2: CGFloat = 4
    /// Buttons inside a row's action group; a dot and its word.
    static let s3: CGFloat = 6
    /// Buttons in a footer; a row's top and bottom padding.
    static let s4: CGFloat = 8
    /// Between cards; a header's and a toolbar's vertical padding.
    static let s5: CGFloat = 12
    /// The window inset, and a sheet's padding: the only value that
    /// touches an edge.
    static let s6: CGFloat = 18

    /// Sizes.
    /// One purpose, one column: Settings, Grants, a single list.
    static let widthSmall: CGFloat = 520
    /// What such a window opens at when its content is taller.
    static let heightSmall: CGFloat = 400
    /// The default window width: a list with a header and maybe a filter.
    static let width: CGFloat = 720
    /// What such a window opens at when its content is taller.
    static let height: CGFloat = 480
    /// Below the width, hide the toolbar before letting a row wrap.
    static let minHeight: CGFloat = 320

    /// A window's minimum height: two thirds of what it opens at. The
    /// rule lives here so a second window cannot pick a third fraction.
    static func minimum(_ height: CGFloat) -> CGFloat {
        (height * 2 / 3).rounded()
    }

    static let sheetWide: CGFloat = 520
    static let button: CGFloat = 22
    static let mark: CGFloat = 34
    static let markEmpty: CGFloat = 56

    // Radii.
    static let control: CGFloat = 6
    static let card: CGFloat = 10
    static let segment: CGFloat = 5

    // Type. Eleven styles, and no italic anywhere.
    static let head = Font.system(size: 15, weight: .semibold)
    static let sub = Font.system(size: 12)
    static let eyebrow = Font.system(size: 11, weight: .medium)
    static let cardTitle = Font.system(size: 13, weight: .semibold)
    static let cardNote = Font.system(size: 12)
    static let rowName = Font.system(size: 13, weight: .semibold)
    static let rowFact = Font.system(size: 11)
    static let button12 = Font.system(size: 12)
    static let emptyTitle = Font.system(size: 14, weight: .semibold)
    static let command = Font.system(size: 11, design: .monospaced)
}

/// The surfaces inside a window, as the fractions of the label colour the
/// design system samples them at. They are relative on purpose: the real
/// window is a translucent material that tints with the wallpaper, so a
/// flat hex would be right in one appearance and wrong in the other.
enum WindowSurface {
    /// A card on the window.
    static let card = Color.primary.opacity(0.09)
    /// A row under the pointer.
    static let hover = Color.primary.opacity(0.05)
    /// Between rows inside a card.
    static let rowLine = Color.primary.opacity(0.07)
    /// Between regions.
    static let separator = Color.primary.opacity(0.10)
    static let segmentTrack = Color.primary.opacity(0.08)
    static let segmentOn = Color.primary.opacity(0.16)
    /// A button inside a row or a card.
    static let quiet = Color.primary.opacity(0.13)
    /// A secondary named action.
    static let secondary = Color.primary.opacity(0.28)
    /// A search field, and the popup button drawn from its tokens.
    static let field = Color.primary.opacity(0.07)
    /// The border of a field or a popup button.
    static let controlLine = Color.primary.opacity(0.16)
    /// The block carrying jit's own words after a failure: a recess, not
    /// an overlay, and the only place raw output belongs on screen.
    static let verbatim = Color.black.opacity(0.20)
}

/// Every button in an app window. The default takes the system accent,
/// because the real app follows the user's: green is the brand mark and a
/// healthy state, never a control.
struct AppButton: ButtonStyle {
    enum Kind {
        /// The one action the window is for. One per region.
        case primary
        /// The other named action.
        case secondary
        /// Anything inside a row or a card.
        case quiet
        /// A link that opens another surface.
        case plain
        /// Deletes something, and never the default.
        case destructive
    }

    var kind: Kind = .quiet

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: bold ? .semibold : .regular))
            .foregroundStyle(label)
            .padding(.horizontal, kind == .plain ? Win.s2 : Win.s5)
            .frame(height: Win.button)
            .background(fill, in: RoundedRectangle(cornerRadius: Win.control, style: .continuous))
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private var bold: Bool {
        kind == .primary || kind == .destructive
    }

    private var fill: Color {
        switch kind {
        case .primary: Color.accentColor
        case .secondary: WindowSurface.secondary
        case .quiet: WindowSurface.quiet
        case .plain: .clear
        case .destructive: Color(StatusMark.red)
        }
    }

    private var label: Color {
        switch kind {
        case .primary, .destructive: .white
        case .plain: Color(StatusMark.accent)
        case .secondary, .quiet: .primary
        }
    }
}

/// The jitpass mark at a state's colour: a dot inside its own soft ring.
/// Hollow is "not yet", the same ring the panel draws before setup.
struct WindowMark: View {
    let tint: Color
    var hollow = false
    var size = Win.mark

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(hollow ? 0.16 : 0.22))
            if hollow {
                Circle().strokeBorder(tint, lineWidth: size * 0.085).padding(size * 0.25)
            } else {
                Circle().fill(tint).padding(size * 0.22)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A state's dot. It never carries the state alone: at 8px the red is
/// 2.3:1 on the window, so every dot has its word beside it.
struct StateDot: View {
    let tint: Color

    var body: some View {
        Circle().fill(tint).frame(width: 8, height: 8)
    }
}

/// A card: the eyebrow that carries its tier, a title and a note, the
/// actions on the title's line, and the rows it lists under a rule.
struct AppCard<Rows: View, Actions: View>: View {
    let eyebrow: String
    let eyebrowTint: Color
    let title: String
    var note: String?
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s4) {
            HStack(spacing: Win.s3) {
                StateDot(tint: eyebrowTint)
                Text(eyebrow).font(Win.eyebrow).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: Win.s5) {
                VStack(alignment: .leading, spacing: Win.s1) {
                    Text(title).font(Win.cardTitle)
                    if let note {
                        Text(note).font(Win.cardNote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Win.s5)
                HStack(spacing: Win.s3) { actions() }
            }
            rows()
        }
        .padding(Win.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
    }
}

/// The rows a card lists, under the rule that separates them from its
/// note, each divided from the next but not from the card's edge.
struct AppCardRows<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(WindowSurface.separator).frame(height: 1)
            content()
        }
    }
}

/// One row: the thing itself, the part that tells it from its neighbours
/// in mono, one fact under it, and at most two verbs pushed right.
struct AppRow<Actions: View>: View {
    let name: String
    var detail: String?
    /// One word after the name, in a chip: "new" on a finding the previous
    /// scan did not have. Its WORD takes the app's action colour, its fill
    /// stays the neutral `app-field`: the row's dot carries severity, the
    /// chip says this is the thing to look at, which is what news is, and a
    /// state colour here would claim a severity the chip cannot know.
    ///
    /// The published design system still says this chip is "never a
    /// colour": that page was not republished, and this is the deliberate
    /// divergence recorded in CLAUDE.md. Do not revert it by reading the
    /// artifact.
    ///
    /// The fill is neutral for a measured reason, not a taste: the word on
    /// `app-field` over a card is 4.91:1, and on a tint of the action
    /// colour it is 4.33:1, under the 4.5:1 floor. The grey word this
    /// replaced was 3.72:1, so colouring it is what brings the chip above
    /// the floor at all.
    var badge: String?
    var fact: String?
    /// A settings row explains what its control costs, and that sentence
    /// is allowed the second line a list row is not.
    var wraps = false
    var last = false
    @ViewBuilder var actions: () -> Actions

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Win.s5) {
                VStack(alignment: .leading, spacing: Win.s1) {
                    HStack(spacing: Win.s3) {
                        // The name is the thing itself: the detail beside it
                        // gives way first ("notion-li…est-users" was the name
                        // squeezed by a mono detail and two buttons).
                        Text(name).font(Win.rowName).lineLimit(1).truncationMode(.middle).layoutPriority(1)
                        if let detail {
                            Text(detail).font(Win.command).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.head)
                        }
                        if let badge {
                            Text(badge).font(Win.eyebrow).foregroundStyle(Color(StatusMark.accent))
                                .textCase(.uppercase)
                                .padding(.horizontal, Win.s2).padding(.vertical, Win.s1)
                                .background(Design.Surface.field)
                                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.box, style: .continuous))
                        }
                    }
                    if let fact {
                        Text(fact).font(Win.rowFact).foregroundStyle(.secondary)
                            .lineLimit(wraps ? nil : 1)
                            .fixedSize(horizontal: false, vertical: wraps)
                    }
                }
                Spacer(minLength: Win.s5)
                HStack(spacing: Win.s3) { actions() }
            }
            .padding(.vertical, Win.s4)
            .padding(.horizontal, Win.s3)
            .background(hovering ? WindowSurface.hover : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Win.segment, style: .continuous))
            .onHover { hovering = $0 }
            if !last {
                Rectangle().fill(WindowSurface.rowLine).frame(height: 1)
            }
        }
    }
}

/// A window with nothing to report says what is true, centred, and offers
/// the one thing there is to do.
struct WindowEmptyState<Actions: View>: View {
    let tint: Color
    var hollow = false
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: Win.s5) {
            WindowMark(tint: tint, hollow: hollow, size: Win.markEmpty)
            Text(title).font(Win.emptyTitle)
            Text(message)
                .font(Win.sub).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
            HStack(spacing: Win.s4) { actions() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, Win.s6)
    }
}

/// How tall a window's body turned out, so the window can open at the
/// height of what it holds instead of a fixed height with nothing under
/// the last card.
struct WindowHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Report this view's height up to the window through
    /// `WindowHeightKey`. Put it on the body's content, not on the window.
    func measureWindowHeight() -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: WindowHeightKey.self, value: proxy.size.height)
        })
    }

    /// A region of a window: the one inset, and the rule that divides it
    /// from the next.
    func windowRegion(vertical: CGFloat = Win.s5, rule: Bool = true) -> some View {
        VStack(spacing: 0) {
            self
                .padding(.horizontal, Win.s6)
                .padding(.vertical, vertical)
                .frame(maxWidth: .infinity, alignment: .leading)
            if rule {
                Rectangle().fill(WindowSurface.separator).frame(height: 1)
            }
        }
    }
}
