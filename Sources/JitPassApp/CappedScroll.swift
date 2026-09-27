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
    /// Told whether the content runs past `maxHeight`, for a caller that
    /// must say so (a security question cannot rely on an overlay scrollbar
    /// that stays hidden until someone scrolls).
    var overflows: ((Bool) -> Void)?
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
        .scrollIndicators(height > maxHeight ? (overflows == nil ? .automatic : .visible) : .never)
        .frame(height: min(height, maxHeight))
        .onPreferenceChange(ContentHeight.self) { new in
            height = new
            overflows?(new > maxHeight)
        }
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
    /// Say under the text when it runs past `lines`: on a question the user
    /// answers (consent), padding that pushes the part that matters out of
    /// view must not be invisible.
    var saysMore = false

    @State private var more = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CappedScroll(
                maxHeight: ceil(NSLayoutManager().defaultLineHeight(for: nsFont)) * CGFloat(lines),
                overflows: saysMore ? { more = $0 } : nil
            ) {
                Text(text).font(font).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if saysMore, more {
                Text("Longer than shown (\(text.count) characters): scroll to read all of it.")
                    .font(.caption).foregroundStyle(Color(StatusMark.amber))
            }
        }
    }
}

private struct ContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
