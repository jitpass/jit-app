// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// How a notification switch that was split out of another reads before
/// anyone has set it: it takes the value of the switch it came from, so
/// an upgrade changes nobody's choice. Nothing stored at all is on, as
/// every notification switch is by default.
public enum NotificationPreference {
    public static func split(own: Bool?, from parent: Bool?) -> Bool {
        own ?? parent ?? true
    }
}
