// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The app's one question before a jit command that deletes secrets,
/// worded from what jit reports right then. For `jit vault rm` that is the
/// dry run: the exact paths, who still uses them and what stops working.
/// The app passes --yes, so this is the only question; when something uses
/// the paths the button is a different, named one and runs
/// --break-profiles, which jit 1.9 demands before it deletes anything in use.
public struct DeleteConfirmation: Equatable, Sendable {
    public var title: String
    public var message: String
    /// The destructive button; nil when there is nothing the app may run
    /// (nothing stored, or the dry run itself failed). When jit ran but
    /// can't tell what uses the paths, it is the break variant.
    public var button: String?
    /// The button runs --break-profiles: Cancel is the default, and the
    /// button is not.
    public var breaks: Bool
    /// What the button runs, without the leading "jit".
    public var arguments: [String]
    /// The exact secrets it deletes: the dry run's expansion, never a group
    /// name that could have grown since.
    public var paths: [String]
    /// False for the one confirmation of this shape that deletes nothing
    /// (`jit profile adopt`): an informational dialog, not a warning.
    public var destructive: Bool

    public init(
        title: String, message: String, button: String?, breaks: Bool, arguments: [String], paths: [String] = [],
        destructive: Bool = true
    ) {
        self.title = title
        self.message = message
        self.button = button
        self.breaks = breaks
        self.arguments = arguments
        self.paths = paths
        self.destructive = destructive
    }
}

public extension VaultRmPlan {
    /// The dialog for this plan. `home` shortens paths to ~.
    func confirmation(home: String = NSHomeDirectory()) -> DeleteConfirmation {
        guard !paths.isEmpty else {
            let names = missing.isEmpty ? "" : " at " + missing.joined(separator: ", ")
            return DeleteConfirmation(
                title: "Nothing to delete", message: "jit has no secret stored\(names).", button: nil, breaks: false, arguments: []
            )
        }
        return isClean ? cleanConfirmation : breakConfirmation(home: home)
    }

    /// When the dry run itself failed: an older jit without --dry-run, or
    /// one that printed no plan. Nothing runs; the app never deletes what it
    /// could not check.
    static func unavailable(_ paths: [String], reason: String) -> DeleteConfirmation {
        let subject = paths.count == 1 ? paths[0] : "\(paths.count) secrets"
        var message = "Nothing was deleted. Before deleting, JitPass asks jit what still uses "
            + (paths.count == 1 ? "the secret" : "them") + ", and jit did not answer:\n\n"
            + (reason.isEmpty ? "(no output)" : reason)
        if reason.contains("unknown flag") || reason.contains("--dry-run") {
            message += "\n\nThat jit is older than 1.9, the first that can say. Update it, "
                + "or delete in the terminal, where jit runs its own check."
        }
        return DeleteConfirmation(title: "Can't check what uses \(subject)", message: message, button: nil, breaks: false, arguments: [])
    }

    /// jit refused after all (something started using a path between the
    /// dry run and the delete). Its own output names who, so the app shows
    /// that rather than a generic failure.
    static func isRefusal(_ output: String) -> Bool {
        output.contains("nothing deleted")
    }

    static func refusalMessage(_ output: String) -> String {
        "jit deleted nothing: something uses these secrets now that did not when the app checked. jit says:\n\n" + output
    }

    // MARK: - Wording

    private var subject: String {
        paths.count == 1 ? paths[0] : "\(paths.count) secrets"
    }

    /// "it" or "them", for the doomed set.
    private var pronoun: String {
        paths.count == 1 ? "it" : "them"
    }

    private var deletes: String {
        paths.count == 1 ? "It deletes the secret and its history for good"
            : "It deletes all \(paths.count) secrets and their history for good"
    }

    private var missingNote: String {
        missing.isEmpty ? "" : " Not stored, so not deleted: \(missing.joined(separator: ", "))."
    }

    /// The command with the paths it deletes: on the line when there are
    /// a few, one per line under it past that, where a long list wrapped
    /// mid-path. What runs is `arguments`, every path in it.
    private func command(_ fixed: [String]) -> String {
        CommandText.shown(fixed, names: paths, noun: ("secret", "secrets"), listedAbove: false)
    }

    private var cleanConfirmation: DeleteConfirmation {
        let arguments = ["vault", "rm", "--yes"] + paths
        let message = "This runs:\n\n\(command(["vault", "rm", "--yes"]))\n\n\(deletes). "
            + "No profile, mount or pointer file jit can find uses \(pronoun)." + missingNote
            + " Nothing asks again. Touch ID follows."
        return DeleteConfirmation(
            title: "Delete \(subject)?", message: message,
            button: paths.count == 1 ? "Delete" : "Delete \(paths.count)", breaks: false, arguments: arguments, paths: paths
        )
    }

    private func breakConfirmation(home: String) -> DeleteConfirmation {
        let users = users
        let arguments = ["vault", "rm", "--break-profiles", "--yes"] + paths
        var parts: [String] = []
        if !users.isEmpty {
            parts.append("Still used by:\n" + users.map { Self.describe($0, total: paths.count, home: home) }.joined(separator: "\n"))
            parts += Self.consequences(users, home: home)
        }
        if let error {
            parts.append("jit can't tell whether \(paths.count == 1 ? "it is" : "they are") in use: \(error). "
                + "If a profile or pointer file still names \(pronoun), what it starts won't start afterwards.")
        } else if users.isEmpty {
            parts.append("jit would refuse this delete without --break-profiles.")
        }
        parts.append("This runs:\n\n\(command(["vault", "rm", "--break-profiles", "--yes"]))\n\n\(deletes), and nothing asks again."
            + missingNote + (users.isEmpty ? " Touch ID follows." : " Touch ID follows, naming what breaks."))
        let inUse = Set(inUse.map(\.path)).count
        let title = if error != nil, users.isEmpty {
            "jit can't tell what uses \(subject)"
        } else if paths.count == 1 {
            "\(paths[0]) is in use"
        } else if inUse < paths.count {
            "\(inUse) of these \(paths.count) secrets are in use"
        } else {
            "These \(paths.count) secrets are in use"
        }
        let button = users.isEmpty ? "Delete Anyway" : "Delete and Break " + Self.brokenLabel(users, home: home)
        return DeleteConfirmation(
            title: title, message: parts.joined(separator: "\n\n"), button: button, breaks: true, arguments: arguments, paths: paths
        )
    }

    /// One user as a bullet, then its launchers and mount, the way
    /// `jit vault rm` prints them.
    private static func describe(_ user: VaultRmUser, total: Int, home: String) -> String {
        let what = usesWhat(user.paths, total: total)
        if let pointer = user.pointerFile {
            return "• \(short(pointer, home)) points at \(what) (jit://)"
        }
        var lines = ["• profile \(user.profile ?? "?") (\(scopeLabel(user, home))) uses \(what)"]
        lines += user.launchedBy.map { "   launched by \(short($0, home))" }
        if let mount = user.mount {
            lines.append("   served by the mount at \(short(mount, home))")
        }
        return lines.joined(separator: "\n")
    }

    /// What breaks, per kind of user: the profiles won't start (and the
    /// launchers that start them fail), a pointer file stops resolving, a
    /// mount serves nothing.
    private static func consequences(_ users: [VaultRmUser], home: String) -> [String] {
        var out: [String] = []
        let profiles = users.compactMap(\.profile)
        if !profiles.isEmpty {
            var launchers: [String] = []
            for user in users where user.profile != nil {
                for launcher in user.launchedBy where !launchers.contains(launcher) {
                    launchers.append(launcher)
                }
            }
            let one = profiles.count == 1
            var line = "After this, \(list(profiles)) won't start"
            if !launchers.isEmpty {
                line += ", and neither will what \(list(launchers.map { short($0, home) })) "
                    + (launchers.count == 1 ? "launches" : "launch") + " through \(one ? "it" : "them")"
            }
            out.append(line + ": a profile missing a secret can't start its tool.")
        }
        let pointers = users.compactMap(\.pointerFile)
        if !pointers.isEmpty {
            out.append("\(list(pointers.map { short($0, home) })) "
                + (pointers.count == 1 ? "stops working: its jit:// pointer names" : "stop working: their jit:// pointers name")
                + " a deleted secret.")
        }
        var mounts: [String] = []
        for mount in users.compactMap(\.mount) where !mounts.contains(mount) {
            mounts.append(mount)
        }
        for mount in mounts {
            let shown = short(mount, home)
            out.append("The mount at \(shown) would serve a file nothing can fill; "
                + "jit migrate remove \(shown) takes file, profile and secrets down together instead.")
        }
        return out
    }

    /// The button's object: the one profile or file by name, else counts.
    static func brokenLabel(_ users: [VaultRmUser], home: String) -> String {
        let profiles = users.compactMap(\.profile)
        let pointers = users.compactMap(\.pointerFile)
        switch (profiles.count, pointers.count) {
        case (1, 0):
            return ellipsis(profiles[0], 32)
        case (0, 1):
            return ellipsis(short(pointers[0], home), 32)
        case (_, 0):
            return "\(profiles.count) Profiles"
        case (0, _):
            return "\(pointers.count) Pointer Files"
        default:
            return "\(profiles.count) Profile\(profiles.count == 1 ? "" : "s") and \(pointers.count) File\(pointers.count == 1 ? "" : "s")"
        }
    }

    /// How much of the doomed set one user holds, as jit words it.
    private static func usesWhat(_ held: [String], total: Int) -> String {
        switch (held.count, total) {
        case (_, 1): "it"
        case (2, 2): "both"
        case let (count, all) where count == all: "all \(all)"
        case (1, _): held[0]
        default: "\(held.count) of them"
        }
    }

    /// "global", or "project ~/proj".
    private static func scopeLabel(_ user: VaultRmUser, _ home: String) -> String {
        if user.scope == "project", let project = user.project {
            return "project " + short(project, home)
        }
        return user.scope ?? "profile"
    }

    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }

    static func short(_ path: String, _ home: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private static func ellipsis(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}
