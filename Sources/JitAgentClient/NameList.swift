// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A list of names said in a sentence, capped so a sheet without a scroll
/// area keeps its buttons on screen: the first few, then a count of the
/// rest ("ACME_KEY, GLOBEX_TOKEN, INITECH_SECRET and 22 more"). A Protect
/// can vault every variable of a big .env, and the full list is in jit's
/// report one disclosure away.
public enum NameList {
    /// How many names a capped list says before counting the rest.
    public static let shown = 5

    /// The names joined by `separator`; past `limit`, the first `limit`
    /// and "and N more". One over the limit is said in full rather than
    /// as "and 1 more", which is no shorter.
    public static func capped(_ names: [String], limit: Int = shown, separator: String = ", ") -> String {
        guard names.count > limit + 1 else {
            return names.joined(separator: separator)
        }
        return names.prefix(limit).joined(separator: separator) + " and \(names.count - limit) more"
    }

    /// The names as a sentence says them: "a", "a and b", "a, b and c".
    /// Uncapped, for a list that is short by nature (a store family).
    public static func spoken(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }
}
