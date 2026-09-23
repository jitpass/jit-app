// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Every profile on this Mac, found without asking where to look: the
/// project roots jit's mount registry records, the folders the running
/// programs work in, and the global store (ProfileDiscovery). Names and
/// key names only; nothing here opens the vault.
enum ProfileStore {
    static func discover(workingDirectories: [String], extraRoots: [String]) -> [DiscoveredProfile] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
            ?? home + "/Library/Application Support"
        return ProfileDiscovery.discover(
            home: home,
            mountsRegistry: support + "/jitpass/mounts.yaml",
            workingDirectories: workingDirectories,
            extraRoots: extraRoots
        )
    }
}
