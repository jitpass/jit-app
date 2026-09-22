// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit

/// Opens a file the scan flagged in the user's editor, at the line the
/// secret sits on when the editor can be told one.
///
/// macOS has no "default editor" either: a `.env` has no type association
/// at all, and `.json` lands in Xcode or TextEdit. So Settings offers the
/// editors installed on this Mac, found by bundle identifier, and the
/// choice is kept in the app's preferences under `EditorApp`. "" means the
/// system default: whatever LaunchServices has for the file, else the
/// first installed editor from the list below. TextEdit is last there on
/// purpose: it is sandboxed and only receives files of types it declares,
/// so a `.tfvars` or `.env` handed to it fails with "you don't have
/// permission" even though the user can read the file.
enum Editor {
    static let preferenceKey = "EditorApp"

    struct Choice: Identifiable {
        let name: String
        let bundleID: String
        /// A URL that opens `path` at `line`, for editors with a scheme
        /// that takes one; nil means open the file and let the editor
        /// land where it likes.
        let lineURL: ((String, Int) -> URL?)?

        var id: String {
            bundleID
        }
    }

    /// Every editor the app knows how to talk to. Only the installed ones
    /// are shown; the order is the order Settings lists them.
    static let known: [Choice] = [
        Choice(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode", lineURL: fileScheme("vscode")),
        Choice(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92", lineURL: fileScheme("cursor")),
        Choice(name: "VSCodium", bundleID: "com.vscodium", lineURL: fileScheme("vscodium")),
        Choice(name: "Zed", bundleID: "dev.zed.Zed", lineURL: fileScheme("zed")),
        Choice(name: "Sublime Text", bundleID: "com.sublimetext.4", lineURL: queryScheme("subl://open?url=", line: "&line=")),
        Choice(name: "BBEdit", bundleID: "com.barebones.bbedit", lineURL: queryScheme("x-bbedit://open?url=", line: "&line=")),
        Choice(name: "TextMate", bundleID: "com.macromates.TextMate", lineURL: queryScheme("txmt://open?url=", line: "&line=")),
        Choice(name: "Nova", bundleID: "com.panic.Nova", lineURL: nil),
        Choice(name: "Xcode", bundleID: "com.apple.dt.Xcode", lineURL: nil),
        Choice(name: "TextEdit", bundleID: "com.apple.TextEdit", lineURL: nil)
    ]

    /// The editors installed on this Mac, for the Settings picker.
    static func installed() -> [Choice] {
        known.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    static func chosen() -> Choice? {
        guard let id = UserDefaults.standard.string(forKey: preferenceKey), !id.isEmpty else {
            return nil
        }
        return known.first { $0.bundleID == id }
    }

    /// Opens `path` at `line` in the chosen editor, or — with no editor
    /// chosen — in the first installed editor that can jump to a line when
    /// there is one to jump to (VS Code, Cursor, VSCodium, Zed, …, in the
    /// order above), else the system default. A finding names a line; an
    /// Open that lands at the top of a 3,000-line transcript and leaves
    /// the reader to search for it has not opened the finding.
    static func open(_ path: String, line: Int?) {
        let file = URL(fileURLWithPath: path)
        if let choice = chosen(), let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: choice.bundleID) {
            if let line, let url = choice.lineURL?(path, line) {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open([file], withApplicationAt: app, configuration: .init()) { _, _ in }
            }
            return
        }
        if let line, let jumper = installed().first(where: { $0.lineURL != nil }), let url = jumper.lineURL?(path, line) {
            NSWorkspace.shared.open(url)
            return
        }
        if NSWorkspace.shared.urlForApplication(toOpen: file) != nil {
            NSWorkspace.shared.open(file)
        } else if let fallback = installed().first {
            openWith(fallback.bundleID, file)
        }
    }

    private static func openWith(_ bundleID: String, _ file: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return
        }
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: .init()) { _, _ in }
    }

    /// Finder with the file selected — for a regular file or a folder,
    /// dotfiles included. A protected file is a named pipe: Finder cannot
    /// select it (`open -R` only activates Finder, on whatever window it
    /// had), so for anything else the folder it sits in opens instead, and
    /// the click always lands somewhere true. Through `open`, a separate
    /// process, so a menu bar app needs no permission to control Finder.
    static func reveal(_ path: String) {
        let type = (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
        if type == .typeRegular || type == .typeDirectory {
            _ = run("/usr/bin/open", ["-R", path])
        } else {
            _ = run("/usr/bin/open", [(path as NSString).deletingLastPathComponent])
        }
    }

    private static func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// `scheme://file/<path>:<line>`, the VS Code family's convention.
    private static func fileScheme(_ scheme: String) -> (String, Int) -> URL? {
        { path, line in
            guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                return nil
            }
            return URL(string: "\(scheme)://file\(encoded):\(line)")
        }
    }

    /// `<prefix>file://<path><line>N`, the older Mac editors' convention.
    private static func queryScheme(_ prefix: String, line lineKey: String) -> (String, Int) -> URL? {
        { path, line in
            guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                return nil
            }
            return URL(string: "\(prefix)file://\(encoded)\(lineKey)\(line)")
        }
    }
}
