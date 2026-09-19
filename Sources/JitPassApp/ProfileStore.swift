// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// The names of the global profiles, read from the manifest file names
/// under ~/.jit/profiles. Names only: a manifest maps variables to vault
/// paths and holds no value, and the app does not open it either way.
enum ProfileStore {
    static func globalNames(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        let dir = ProfileFiles.directory(home: home.path)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files
            .filter { $0.hasSuffix(".yaml") }
            .map { String($0.dropLast(".yaml".count)) }
            .sorted()
    }
}
