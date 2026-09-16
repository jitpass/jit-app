// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Folders every scan skips, kept in the app's preferences and passed to
/// `jit scan --exclude` on each run, so the CLI does the skipping and the
/// score reflects it. Paths only, absolute, deduplicated.
enum ScanExcludes {
    static let key = "ScanExcludes"

    static func load() -> [String] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).sorted()
    }

    static func save(_ paths: [String]) {
        UserDefaults.standard.set(Array(Set(paths)).sorted(), forKey: key)
    }

    static func add(_ path: String) -> [String] {
        let updated = load() + [path]
        save(updated)
        return load()
    }

    static func remove(_ path: String) -> [String] {
        save(load().filter { $0 != path })
        return load()
    }
}
