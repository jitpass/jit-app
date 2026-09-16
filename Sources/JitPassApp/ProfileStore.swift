// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The names of the global profiles, read from the manifest file names
/// under ~/.jit/profiles. Names only: a manifest maps variables to vault
/// paths and holds no value, and the app does not open it either way.
enum ProfileStore {
    static func manifest(named name: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".jit/profiles/\(name).yaml")
    }

    /// Removes a global profile's manifest, moving it to the Trash rather
    /// than unlinking it, so the one thing the app deletes is recoverable.
    /// The vault is untouched: a manifest holds names, never values.
    static func trashGlobal(named name: String) throws {
        try FileManager.default.trashItem(at: manifest(named: name), resultingItemURL: nil)
    }

    static func globalNames(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        let dir = home.appendingPathComponent(".jit/profiles")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files
            .filter { $0.hasSuffix(".yaml") }
            .map { String($0.dropLast(".yaml".count)) }
            .sorted()
    }
}
