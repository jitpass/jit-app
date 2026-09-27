// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A caller as jit records it: `by` is the full command line the kernel
/// reports, or for a mount serve the bare executable path, and either can
/// hold spaces. Splitting on the first space named "/Applications/Acme
/// Studio.app/…/acme" "Acme"; taking the last "/" of the whole line named
/// "node /Users/x/proj/server.js" "server.js" (2026-09-27).
public struct CallerCommand: Equatable, Sendable {
    /// The program's name: "acme", "Acme Helper", "node".
    public var program: String
    /// What followed it on the command line, "" when nothing did.
    public var arguments: String

    /// Nil for an empty line.
    ///
    /// A line is ambiguous on its own: "/usr/local/bin/node dist/server.js"
    /// and "/Users/x/My Tools/bin/fetch" both look like a path with a space
    /// in it. The Mac is not ambiguous: the program is the longest prefix of
    /// the line that is an executable file, so that is asked first. Only a
    /// program no longer on disk falls back to reading the text, and that
    /// never glues an argument onto the program (review, 2026-09-27: "node
    /// dist/server.js" was named "server.js", so the interpreter that asked
    /// was never named).
    /// `isExecutable` is for tests: nil, the default, is the real file
    /// system, remembered per line (`cachedExecutableEnd`).
    public init?(_ line: String?, isExecutable: ((String) -> Bool)? = nil) {
        let line = (line ?? "").trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else {
            return nil
        }
        let end = isExecutable.map { Self.executableEnd(line, isExecutable: $0) } ?? Self.cachedExecutableEnd(line)
        if let end {
            let path = line[..<end]
            program = String(path.split(separator: "/").last ?? path)
            arguments = String(line[end...]).trimmingCharacters(in: .whitespaces)
            return
        }
        // Fallback, from the text. An app's executable sits in the FIRST
        // Contents/MacOS of the line (a later one is an argument's), and is
        // usually named for its bundle ("Acme Helper.app/…/Acme Helper"),
        // which may hold spaces; otherwise it ends at the first space.
        if let macOS = line.range(of: "/Contents/MacOS/"), line.hasPrefix("/") {
            let rest = line[macOS.upperBound...]
            let bundle = line[..<macOS.lowerBound].split(separator: "/").last
                .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : String($0) } ?? ""
            let end = Self.nameEnd(rest, bundle: bundle)
            program = String(rest[..<end])
            arguments = String(rest[end...]).trimmingCharacters(in: .whitespaces)
            if !program.isEmpty {
                return
            }
        }
        var words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let path = words.removeFirst()
        program = String(path.split(separator: "/").last ?? Substring(path))
        arguments = words.joined(separator: " ")
    }

    /// Where an app executable's name ends in rest (the text after
    /// Contents/MacOS/): after the bundle's own name when rest starts with it
    /// as a whole word, else at the first space.
    static func nameEnd(_ rest: Substring, bundle: String) -> Substring.Index {
        if !bundle.isEmpty, rest.hasPrefix(bundle) {
            let after = rest.index(rest.startIndex, offsetBy: bundle.count)
            if after == rest.endIndex || rest[after] == " " {
                return after
            }
        }
        return rest.firstIndex(of: " ") ?? rest.endIndex
    }

    /// Where the executable's path ends in line: after the longest prefix,
    /// cut at a space or the end, that is an executable file. Nil when none
    /// is, or the line is not an absolute path.
    static func executableEnd(_ line: String, isExecutable: (String) -> Bool) -> String.Index? {
        guard line.hasPrefix("/") else {
            return nil
        }
        var cuts = line.indices.filter { line[$0] == " " }
        cuts.append(line.endIndex)
        for cut in cuts.reversed() where isExecutable(String(line[..<cut])) {
            return cut
        }
        return nil
    }

    /// executableEnd, remembered per line for the real file system: every
    /// audit row and every AI Agents refresh names its program, on the main
    /// thread, and a week of events repeats the same few command lines, so
    /// each asks the disk once (review, 2026-09-27). Offsets, not indexes,
    /// so an entry outlives the String it was computed from. Emptied past
    /// 1,024 lines. A test's own isExecutable is never cached.
    private nonisolated(unsafe) static var ends: [String: Int?] = [:]
    private static let endsLock = NSLock()

    static func cachedExecutableEnd(_ line: String) -> String.Index? {
        endsLock.lock()
        let known = ends[line]
        endsLock.unlock()
        if let known {
            return known.map { line.index(line.startIndex, offsetBy: $0) }
        }
        let end = executableEnd(line, isExecutable: isExecutableFile)
        endsLock.lock()
        if ends.count >= 1024 {
            ends.removeAll()
        }
        ends[line] = end.map { line.distance(from: line.startIndex, to: $0) }
        endsLock.unlock()
        return end
    }

    /// An executable regular file, not a folder (an app bundle is one).
    public static func isExecutableFile(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    /// The program and its arguments, the path cut to the name:
    /// "acme run python server.py", "node /Users/x/proj/server.js".
    public var shown: String {
        arguments.isEmpty ? program : program + " " + arguments
    }
}
