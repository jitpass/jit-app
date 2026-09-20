// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The Doctor window's filter: All, the tiers that have something, and
/// Ignored while anything is. A tier with nothing in it is left out
/// rather than greyed out — a control that can never be pressed is one
/// more number on a screen that had six of them, and "Recommended 0" told
/// nobody anything.
public enum DoctorTab: Hashable, Sendable {
    case all
    case tier(DoctorBoard.Tier)
    case ignored
}

public struct DoctorTabItem: Equatable, Sendable, Identifiable {
    public var tab: DoctorTab
    public var title: String
    public var count: Int

    public var id: DoctorTab {
        tab
    }
}

public extension DoctorBoard {
    /// What one tab counts: the things a reader acts on, not the cards
    /// they are grouped into. Four leftover files in one card are four.
    func toFix(in tier: Tier) -> Int {
        cards(in: tier).reduce(0) { $0 + $1.toFix }
    }

    var toFix: Int {
        cards.reduce(0) { $0 + $1.toFix }
    }

    var tabs: [DoctorTabItem] {
        var items = [DoctorTabItem(tab: .all, title: "All", count: toFix)]
        for tier in Tier.allCases {
            let count = toFix(in: tier)
            if count > 0 {
                items.append(DoctorTabItem(tab: .tier(tier), title: tier.title, count: count))
            }
        }
        if !ignored.isEmpty {
            items.append(DoctorTabItem(tab: .ignored, title: "Ignored", count: ignored.count))
        }
        return items
    }

    /// The tab to show for the one selected: one whose findings are all
    /// fixed falls back to All, so a fix never leaves the window on a
    /// filter that now hides everything.
    func showing(_ tab: DoctorTab) -> DoctorTab {
        switch tab {
        case .ignored:
            ignored.isEmpty ? .all : .ignored
        case let .tier(tier):
            cards(in: tier).isEmpty ? .all : tab
        case .all:
            .all
        }
    }

    /// Whether a tier's cards are on the tab: All shows every tier, a
    /// tier's own tab its own, and Ignored none.
    func shows(_ tier: Tier, on tab: DoctorTab) -> Bool {
        let tab = showing(tab)
        return tab == .all || tab == .tier(tier)
    }
}
