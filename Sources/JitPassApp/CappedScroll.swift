// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import SwiftUI

/// Content that can run to any length (a reader's kernel command line, a
/// job's argv, every profile on the Mac) shown at its own height up to
/// `maxHeight`, and past it in a scroll area of that height, so the
/// buttons under it always stay on screen. The height is measured rather
/// than left to the scroll view, which would otherwise take its full cap
/// for one short line.
struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: () -> Content

    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeight.self, value: proxy.size.height)
                })
        }
        .scrollIndicators(height > maxHeight ? .automatic : .never)
        .frame(height: min(height, maxHeight))
        .onPreferenceChange(ContentHeight.self) { height = $0 }
    }
}

/// Text in a `CappedScroll` sized in lines of its own font: selectable,
/// all of it, whether or not it scrolls.
struct CappedText: View {
    let text: String
    var font = Win.command
    /// The NSFont `font` is drawn in, for its line height.
    var nsFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    var lines = 4

    var body: some View {
        CappedScroll(maxHeight: ceil(NSLayoutManager().defaultLineHeight(for: nsFont)) * CGFloat(lines)) {
            Text(text).font(font).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
