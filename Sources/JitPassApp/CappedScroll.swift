// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import SwiftUI

/// Content that can run to any length (a job's argv, every profile on the
/// Mac) shown at its own height up to
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
        .onPreferenceChange(ContentHeight.self) { new in
            height = new
        }
    }
}

private struct ContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
