// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The Doctor window's tabs: All, one per tier, and Ignored, which is there
/// only while something is ignored. All is the three tiers; the ignored
/// findings are counted by their own tab alone.
public enum DoctorTab: Hashable, Sendable {
    case all
    case tier(DoctorBoard.Tier)
    case ignored
}

public struct DoctorTabItem: Equatable, Sendable, Identifiable {
    public var tab: DoctorTab
    public var title: String
    public var count: Int
    /// A tier with nothing in it stays in its place, greyed out.
    public var enabled: Bool

    public var id: DoctorTab {
        tab
    }
}

public extension DoctorBoard {
    var tabs: [DoctorTabItem] {
        var items = [DoctorTabItem(tab: .all, title: "All", count: cards.count, enabled: true)]
        for tier in Tier.allCases {
            let count = cards(in: tier).count
            items.append(DoctorTabItem(tab: .tier(tier), title: tier.title, count: count, enabled: count > 0))
        }
        if !ignored.isEmpty {
            items.append(DoctorTabItem(tab: .ignored, title: "Ignored", count: ignored.count, enabled: true))
        }
        return items
    }

    /// The tab to show for the one selected: Ignored falls back to All once
    /// nothing is ignored any more.
    func showing(_ tab: DoctorTab) -> DoctorTab {
        tab == .ignored && ignored.isEmpty ? .all : tab
    }

    /// Whether a tier's section is on the tab: All shows every tier, a
    /// tier's tab its own, and Ignored none.
    func shows(_ tier: Tier, on tab: DoctorTab) -> Bool {
        let tab = showing(tab)
        return tab == .all || tab == .tier(tier)
    }
}
