// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Where the last whole-Mac scan lives between launches: one JSON file in
/// the app's own Application Support folder, readable by this user only.
/// Best-effort both ways — a file that cannot be read is a Mac not
/// scanned yet, and a save that fails costs the next launch a scan, not
/// the user a fact.
enum LastScanStore {
    static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("JitPass", isDirectory: true)
            .appendingPathComponent("last-scan.json")
    }

    static func load() -> LastScan? {
        guard let url, let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? LastScan.decode(data)
    }

    static func save(_ scan: LastScan) {
        guard let url, let data = try? scan.encoded() else {
            return
        }
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func clear() {
        guard let url else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}
