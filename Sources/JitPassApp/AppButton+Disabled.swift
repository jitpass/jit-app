// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import SwiftUI

/// A disabled button reads as one: the design system's `[disabled]`
/// opacity. A button style cannot read the environment itself; a view can.
struct DimWhenDisabled: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.opacity(isEnabled ? 1 : Design.Opacity.disabled)
    }
}
