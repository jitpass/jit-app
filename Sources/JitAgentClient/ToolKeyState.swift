// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A key exported from a shell config: where, which variable, and the
/// vault path `jit migrate` gives it (its profile is the file's name
/// without the dot, as migrate names it).
public struct ShellConfigKey: Equatable, Sendable {
    public var file: String
    public var name: String
    public var profile: String

    public init(file: String, name: String, profile: String) {
        self.file = file
        self.name = name
        self.profile = profile
    }

    public var vaultPath: String {
        profile + "/" + name
    }
}

/// The answer to "is there a key to protect": already handled, found
/// somewhere on this Mac, looked and found nothing, or not looked yet.
public enum ToolKeyState: Sendable, Equatable {
    case protected
    case found(String)
    case none
    case unknown

    /// A key was found somewhere jit can take it from.
    public var found: Bool {
        if case .found = self {
            return true
        }
        return false
    }

    /// A key sits in a plaintext file, which is the state worth a colour:
    /// a token in a tool's own keychain login is encrypted at rest, and
    /// wrapping it is an improvement, not a fix.
    public var needsAction: Bool {
        if case let .found(source) = self {
            return source.hasPrefix("~") || source.hasPrefix("/")
        }
        return false
    }
}
