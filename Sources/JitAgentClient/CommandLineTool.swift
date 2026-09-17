// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Whether the `jit` a terminal runs is the one inside this app. The
/// `jitpass` cask makes that so with a symlink; a copy downloaded from the
/// website has to make it so itself, and this is the check and the choice
/// of where the link goes. Pure path logic, so it is testable; the app does
/// the linking.
public enum CommandLineTool {
    public enum State: Equatable, Sendable {
        /// `jit` on PATH resolves into this app.
        case linked(String)
        /// `jit` on PATH is a different binary: an older tarball install, a
        /// previous app, a build of the user's own.
        case other(String)
        /// No `jit` on PATH.
        case missing
    }

    /// Where a link goes, in order of preference: Homebrew's bin needs no
    /// password when it exists, /usr/local/bin always needs one.
    public static let usualDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// Where the `jitpass` cask keeps its bookkeeping; when it is there,
    /// updates go through `brew upgrade` and the link is Homebrew's to keep.
    public static let caskrooms = ["/opt/homebrew/Caskroom/jitpass", "/usr/local/Caskroom/jitpass"]

    /// The first `jit` on `path`, resolved through symlinks and compared
    /// with the bundled copy the same way.
    public static func state(bundled: String, path: String?, fileManager: FileManager = .default) -> State {
        let directories = (path ?? usualDirectories.joined(separator: ":")).split(separator: ":").map(String.init)
        for directory in directories where !directory.isEmpty {
            let candidate = (directory as NSString).appendingPathComponent("jit")
            guard fileManager.isExecutableFile(atPath: candidate) else {
                continue
            }
            return resolved(candidate) == resolved(bundled) ? .linked(candidate) : .other(candidate)
        }
        return .missing
    }

    /// Where a new link should go and whether that takes an administrator
    /// password: the first usual directory that is on PATH and writable,
    /// else /usr/local/bin with the password.
    public static func linkTarget(path: String?, fileManager: FileManager = .default) -> (directory: String, needsAdmin: Bool) {
        let onPath = Set((path ?? "").split(separator: ":").map(String.init))
        for directory in usualDirectories where onPath.contains(directory) || path == nil {
            if isWritableDirectory(directory, fileManager: fileManager) {
                return (directory, false)
            }
        }
        return ("/usr/local/bin", true)
    }

    private static func isWritableDirectory(_ directory: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directory, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue && fileManager.isWritableFile(atPath: directory)
    }

    public static func installedByHomebrew(fileManager: FileManager = .default) -> Bool {
        caskrooms.contains { fileManager.fileExists(atPath: $0) }
    }

    private static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
