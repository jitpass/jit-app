// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The in-app Protect All: files for one migrate call, tools for one
/// wrap each.
public struct ProtectPlan: Equatable, Sendable {
    public var migrate: [String] = []
    public var wrap: [String] = []

    public init(migrate: [String] = [], wrap: [String] = []) {
        self.migrate = migrate
        self.wrap = wrap
    }

    public var isEmpty: Bool {
        migrate.isEmpty && wrap.isEmpty
    }

    public var count: Int {
        migrate.count + wrap.count
    }
}
