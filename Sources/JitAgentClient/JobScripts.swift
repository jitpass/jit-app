// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A script in a job's folder and the command it becomes: what New AI Job
/// offers under Runs, so a job is picked rather than typed. A suggestion
/// only: `job_preview` checks whatever is chosen, exactly as it checks a
/// typed command, and refuses what approval would.
public struct JobScript: Sendable, Equatable, Identifiable {
    /// The file's name in the folder.
    public var file: String
    public var argv: [String]

    public var id: String {
        file
    }

    public init(file: String, argv: [String]) {
        self.file = file
        self.argv = argv
    }

    public var command: String {
        JobDraft.join(argv)
    }
}

public enum JobScripts {
    /// The scripts at the top level of `folder`, by name. Only the top level:
    /// a folder holding a `node_modules` or a `.venv` would list thousands,
    /// and anything else is one "Another command…" away. Python runs from the
    /// folder's own virtualenv when it has one, since that is how the script
    /// runs by hand there.
    public static func suggest(in folder: String, fileManager: FileManager = .default) -> [JobScript] {
        guard !folder.isEmpty, let names = try? fileManager.contentsOfDirectory(atPath: folder) else {
            return []
        }
        let python = [".venv/bin/python", "venv/bin/python"].first {
            fileManager.isExecutableFile(atPath: (folder as NSString).appendingPathComponent($0))
        } ?? "python3"
        var scripts: [JobScript] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let path = (folder as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            let executable = fileManager.isExecutableFile(atPath: path)
            switch (name as NSString).pathExtension.lowercased() {
            case "py":
                scripts.append(JobScript(file: name, argv: [python, name]))
            case "sh", "bash", "zsh":
                scripts.append(JobScript(file: name, argv: executable ? ["./" + name] : ["sh", name]))
            case "js", "mjs", "cjs":
                scripts.append(JobScript(file: name, argv: ["node", name]))
            case "rb":
                scripts.append(JobScript(file: name, argv: ["ruby", name]))
            case "":
                if executable {
                    scripts.append(JobScript(file: name, argv: ["./" + name]))
                }
            default:
                continue
            }
        }
        return scripts
    }
}
