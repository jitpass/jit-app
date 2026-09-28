// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The label a vault command runs under: what its row or sheet matches to
/// say it is waiting, failed, or was cancelled, and nothing else's.
public enum VaultCommandLabel {
    /// Move Out / Move to Vault: the one path, or how many.
    public static func move(_ paths: [String]) -> String {
        paths.count == 1 ? paths[0] : "\(paths.count) values"
    }

    /// Move Them Out…, its check and its run.
    public static let settingsCheck = "the old profiles"

    /// Whether a command's state is this sheet's to show: it is running
    /// under the sheet's label, or it ended there.
    public static func belongs(busy: String?, endedFor: String?, to owner: String) -> Bool {
        busy == owner || (busy == nil && endedFor == owner)
    }
}
