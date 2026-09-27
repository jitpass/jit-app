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
    public init?(_ line: String?) {
        let line = (line ?? "").trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else {
            return nil
        }
        // An app's executable sits in Contents/MacOS, and its name may
        // hold spaces ("Acme Helper"): it runs to the first argument.
        if let macOS = line.range(of: "/Contents/MacOS/", options: .backwards) {
            let rest = line[macOS.upperBound...]
            let cut = [" -", " /"].compactMap { rest.range(of: $0)?.lowerBound }.min() ?? rest.endIndex
            program = String(rest[..<cut])
            arguments = String(rest[cut...]).trimmingCharacters(in: .whitespaces)
            if !program.isEmpty {
                return
            }
        }
        var words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var path = words.removeFirst()
        // A path with a space goes on in words that hold a "/" and are
        // not an argument of their own ("-x", "/other/path").
        if path.hasPrefix("/") {
            while let next = words.first, next.contains("/"), !next.hasPrefix("/"), !next.hasPrefix("-") {
                path += " " + words.removeFirst()
            }
        }
        program = String(path.split(separator: "/").last ?? Substring(path))
        arguments = words.joined(separator: " ")
    }

    /// The program and its arguments, the path cut to the name:
    /// "acme run python server.py", "node /Users/x/proj/server.js".
    public var shown: String {
        arguments.isEmpty ? program : program + " " + arguments
    }
}
