// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import SwiftUI

/// The keys inside a project, as chips that wrap: monospaced so
/// `JAMF_EA_NAME` and `JAMF_EA_DEV_SECRETS` read as the names they are,
/// and boxed so a long project stays scannable instead of running into one
/// line. They are the whole reason a row opens.
struct KeyChips: View {
    let keys: [String]

    init(_ keys: [String]) {
        self.keys = keys
    }

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 5) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.09)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Left to right, wrapping at the container's width. SwiftUI has no flow
/// stack, and a project can hold eight keys of very different lengths.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
