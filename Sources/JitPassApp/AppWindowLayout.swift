// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import SwiftUI

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
