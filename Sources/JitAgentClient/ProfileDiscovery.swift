// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One profile jit can find on this Mac: its name, the project folder it
/// sits beside (nil for the global store), the manifest file, and the
/// variable names it maps. Names only: a manifest maps variables to vault
/// paths and holds no value, and this never opens the vault.
public struct DiscoveredProfile: Sendable, Equatable, Hashable, Identifiable {
    public var name: String
    /// The project directory whose `.jit/profiles` holds the manifest; nil
    /// for `~/.jit/profiles`.
    public var root: String?
    public var manifestPath: String
    public var keys: [String]
    /// The vault paths the keys map to, in the same order. A grant covers
    /// these, so a path the vault does not hold is what makes a profile
    /// one the service would refuse.
    public var paths: [String]

    public var id: String {
        manifestPath
    }

    public init(name: String, root: String?, manifestPath: String, keys: [String], paths: [String] = []) {
        self.name = name
        self.root = root
        self.manifestPath = manifestPath
        self.keys = keys
        self.paths = paths
    }

    /// The paths the vault lacks, given what it holds. Empty means every
    /// secret this profile names is there.
    public func missing(from vaultPaths: Set<String>) -> [String] {
        paths.filter { !vaultPaths.contains($0) }
    }

    /// What a grant sends: the name and its folder.
    public var grantProfile: GrantProfile {
        GrantProfile(name: name, root: root)
    }
}

/// Finds every profile on the Mac without asking the user where to look
/// (design/standing-grants.md, "No folder is ever chosen"). Three sources,
/// unioned and deduped by manifest path: the project roots the mount
/// registry records, the working directories of the running programs and
/// their ancestors up to home, and the global store. "Add a folder" covers
/// anything missed and is never the first step.
public enum ProfileDiscovery {
    /// The manifests folder inside a project or home.
    public static let storeSubpath = ".jit/profiles"

    public static func discover(
        home: String,
        mountsRegistry: String,
        workingDirectories: [String],
        extraRoots: [String] = [],
        fileManager: FileManager = .default
    ) -> [DiscoveredProfile] {
        var roots: [String] = []
        var seenRoots: Set<String> = []
        func addRoot(_ root: String) {
            let clean = (root as NSString).standardizingPath
            guard !clean.isEmpty, !seenRoots.contains(clean) else {
                return
            }
            seenRoots.insert(clean)
            roots.append(clean)
        }
        for path in registryProfilePaths(mountsRegistry) {
            addRoot(projectRoot(ofManifest: path))
        }
        for cwd in workingDirectories {
            for dir in ancestors(of: cwd, upTo: home) where hasStore(dir, fileManager) {
                addRoot(dir)
            }
        }
        for root in extraRoots {
            addRoot(root)
        }

        var out: [DiscoveredProfile] = []
        var seenManifests: Set<String> = []
        let cleanHome = (home as NSString).standardizingPath
        func take(_ found: [DiscoveredProfile]) {
            for profile in found where !seenManifests.contains(profile.manifestPath) {
                seenManifests.insert(profile.manifestPath)
                out.append(profile)
            }
        }
        for root in roots where root != cleanHome {
            take(profiles(in: root, isGlobal: false, fileManager: fileManager))
        }
        take(profiles(in: cleanHome, isGlobal: true, fileManager: fileManager))
        return out.sorted {
            $0.name == $1.name ? ($0.root ?? "") < ($1.root ?? "") : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// The `profile_path` values in jit's mount registry (`mounts.yaml`):
    /// absolute manifest paths, one per mount. The file is a small YAML list
    /// jit writes itself; the one field this needs is read by its key.
    static func registryProfilePaths(_ registry: String) -> [String] {
        guard let text = try? String(contentsOfFile: registry, encoding: .utf8) else {
            return []
        }
        return text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("profile_path:") else {
                return nil
            }
            let value = trimmed.dropFirst("profile_path:".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
    }

    /// `<root>/.jit/profiles/<name>.yaml` -> `<root>`.
    static func projectRoot(ofManifest path: String) -> String {
        ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
            .replacingOccurrences(of: "/.jit", with: "", options: [.anchored, .backwards])
    }

    static func hasStore(_ dir: String, _ fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: (dir as NSString).appendingPathComponent(storeSubpath))
    }

    /// `dir`, its parent, and so on, stopping at `home` (included) or the
    /// root. A folder outside home is checked alone.
    static func ancestors(of dir: String, upTo home: String) -> [String] {
        var out: [String] = []
        var cur = (dir as NSString).standardizingPath
        let stop = (home as NSString).standardizingPath
        while !cur.isEmpty, cur != "/" {
            out.append(cur)
            if cur == stop || !cur.hasPrefix(stop + "/") {
                break
            }
            cur = (cur as NSString).deletingLastPathComponent
        }
        return out
    }

    static func profiles(in root: String, isGlobal: Bool, fileManager: FileManager) -> [DiscoveredProfile] {
        let dir = (root as NSString).appendingPathComponent(storeSubpath)
        guard let files = try? fileManager.contentsOfDirectory(atPath: dir) else {
            return []
        }
        return files.sorted().compactMap { file in
            let ext = (file as NSString).pathExtension
            guard ext == "yaml" || ext == "yml" else {
                return nil
            }
            let path = (dir as NSString).appendingPathComponent(file)
            let entries = manifestEntries(path)
            return DiscoveredProfile(
                name: (file as NSString).deletingPathExtension,
                root: isGlobal ? nil : root,
                manifestPath: path,
                keys: entries.map(\.key),
                paths: entries.map(\.path)
            )
        }
    }

    /// The variable names a manifest maps and the vault paths they map to,
    /// in file order. A manifest is a flat `NAME: vault/path` map; anything
    /// else on a line is not an entry.
    static func manifestEntries(_ path: String) -> [(key: String, path: String)] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        var entries: [(key: String, path: String)] = []
        for line in text.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("#") else {
                continue
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), !(key.first?.isNumber ?? true) else {
                continue
            }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            entries.append((key: key, path: value))
        }
        return entries
    }

    static func manifestKeys(_ path: String) -> [String] {
        manifestEntries(path).map(\.key)
    }
}
