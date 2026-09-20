// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What each finding kind is CALLED in the Doctor window, and the sentence
/// under it. Separate from DoctorAdvice's button building because it answers
/// a different question — what this is, rather than what to do about it —
/// and because a kind added without an entry here falls through to a bare
/// capitalized version of jit's own internal noun, which is how a red card
/// once read "Stale Pointers" with no explanation at all.
/// What the window's header says when one kind is the whole of Fix now:
/// the count in the reader's own nouns, the sentence under it, and the
/// mark that goes with what that sentence claims. A kind with no entry
/// falls back to counting problems in red, which is right for the kinds
/// whose findings really do stop a tool.
public struct DoctorHeading: Equatable, Sendable {
    public var one: String
    /// "%d" is the count.
    public var many: String
    public var note: String
    public var mark: DoctorBoard.Mark

    public func headline(_ count: Int) -> String {
        count == 1 ? one : many.replacingOccurrences(of: "%d", with: "\(count)")
    }
}

extension DoctorAdvice {
    /// Kinds that word the header themselves. Deliberately few: a kind
    /// belongs here only when the generic "N problems to fix" in red would
    /// say something untrue about it.
    public static let headings: [String: DoctorHeading] = [
        // These break nothing. jit wrote the files, nothing reads them,
        // and the card's own note says so — under a header that used to
        // call them a problem and a mark that used to be red.
        "stale_pointers": DoctorHeading(
            one: "1 leftover file to clear",
            many: "%d leftover files to clear",
            note: "Nothing is failing. jit wrote these notes, and the secrets they name are gone from the vault.",
            mark: .amber
        )
    ]

    static let titles: [String: (title: String, note: String?)] = [
        "missing": (
            "Missing secrets",
            "A profile points at a secret the vault does not hold; a tool launched through it won't start."
        ),
        "corrupt": ("Unreadable secrets", "The stored value is not in a format this jit can decrypt."),
        "parse": ("Profiles that won't load", nil),
        "not_found": ("Profile not found", nil),
        "vault_error": ("Vault errors", nil),
        "bad_path": ("Bad secret paths", nil),
        "vault_key": ("Master key missing", "Without this Mac's master key nothing in the vault decrypts."),
        "rekey": ("Unfinished key rotation", "Every vault write is refused until the rotation completes."),
        "wrap": ("Broken wrapped tools", "The tool now runs unwrapped, or not at all."),
        "mcp": ("Broken MCP entries", nil),
        "mcp_nested": (
            "Doubly wrapped MCP entries",
            "Still working, but the server launches through jit twice. Migrating again collapses it to one."
        ),
        "jit_path": ("Stale jit paths", "A credential helper points at a jit binary that is gone."),
        "1password": ("1Password CLI", nil),
        "1password_link": (
            "Broken 1Password links",
            "The 1Password item a secret links to does not resolve. Fix the item in 1Password, "
                + "or relink it in the terminal with jit vault link <path> <op://…>."
        ),
        // A project jit knew about, found somewhere else. The title says the
        // event rather than the symptom, because the symptom ("a registered
        // mount is gone") is what jit used to say and what sent people to
        // unmount a project that was alive.
        "mount_moved": (
            "Projects that moved",
            "The folder was renamed or moved, so jit is still serving the old location — which means nothing. "
                + "Re-pointing it touches no secret."
        ),
        "mount_unregistered": (
            "Mounts this Mac doesn't serve",
            "A copied or cloned project brings its mounted file but never the registration, "
                + "so anything reading that file waits forever. Register it, or delete the file."
        ),
        // Without an entry here the kind fell through to a bare, capitalized
        // "Stale Pointers" with no note at all — a red card whose title was
        // jit's internal noun and whose explanation was nothing, on the one
        // surface that exists to explain.
        "stale_pointers": (
            "Leftover jit records",
            "A file jit wrote lists secrets the vault no longer has. Nothing reads it, so the tool beside "
                + "it is what to check: store the values, or delete the file."
        ),
        "orphan": ("Orphaned secrets", "In the vault but referenced by no profile jit can see. Harmless, but dead weight."),
        "duplicates": ("Possible duplicates", "Vault groups that look like the same file stored twice."),
        "origin_gone": (
            "Origin files gone",
            "The file these were migrated from no longer exists. Nothing to do if you still use them: the vault is where they live now."
        ),
        "shadowed": ("Shadowed profiles", "A project profile with the same name wins; the global copy is ignored there."),
        "service": ("Background service", nil),
        "backup": ("Backup", nil),
        "mount": ("Mounts", nil),
        "mount_stale": (
            "Stale mounts",
            "Registered mounts whose project was deleted without unmounting first. Unmounting touches no secret."
        ),
        "wrap_env": ("Wrapped tools, this shell only", "Only true of the shell the check ran in."),
        "audit": ("Audit log", nil),
        "install": (
            "Extra jit installs",
            "PATH order decides which copy runs. The Homebrew copy is this app's: brew uninstall jitpass removes JitPass too."
        ),
        "jit_path_upgrade": ("Version-pinned jit paths", "Still working, but the path will break on the next Homebrew upgrade."),
        "completion": ("Shell completion", nil),
        "legacy_envelope": ("Old secret format", nil)
    ].merging(ownershipTitles) { known, _ in known }
}
