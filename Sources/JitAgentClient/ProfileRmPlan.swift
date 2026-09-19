// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// `jit profile rm --dry-run --format json <name>` (jit 1.10+): what
/// removing a global profile deletes, keeps and can't find, and whether
/// anything known still launches it. Prompt-free, writes nothing, read the
/// moment Remove Profile is clicked. This is the safe replacement for the
/// Delete Profile the app dropped in 1.9: that one trashed the manifest
/// with no launcher check; jit refuses a profile anything known launches,
/// reads every launcher source strictly, and deletes only secrets nothing
/// else uses.
public struct ProfileRmPlan: Decodable, Sendable, Equatable {
    public var profile: String
    public var scope: String?
    /// Everything known that launches it; any one refuses the delete.
    public var launchers: [DoctorLauncher]
    /// Stored, and nothing else uses them: deleted with the profile.
    public var deleteSecrets: [String]
    /// Stored, and another profile or pointer file uses them: kept.
    public var keepSecrets: [String]
    /// Named by the profile, not in the vault.
    public var missingSecrets: [String]
    /// The launcher walk covered all of home. False means a directory jit
    /// could not enter might hold a launcher; absent counts as false.
    public var coverageComplete: Bool
    public var refused: Bool
    /// jit could not read a launcher source; it then refuses too.
    public var error: String?

    enum CodingKeys: String, CodingKey {
        case profile, scope, launchers, refused, error
        case deleteSecrets = "delete_secrets"
        case keepSecrets = "keep_secrets"
        case missingSecrets = "missing_secrets"
        case coverageComplete = "coverage_complete"
    }

    public init(
        profile: String, launchers: [DoctorLauncher] = [], deleteSecrets: [String] = [], keepSecrets: [String] = [],
        missingSecrets: [String] = [], coverageComplete: Bool = true, refused: Bool = false, error: String? = nil
    ) {
        self.profile = profile
        scope = "global"
        self.launchers = launchers
        self.deleteSecrets = deleteSecrets
        self.keepSecrets = keepSecrets
        self.missingSecrets = missingSecrets
        self.coverageComplete = coverageComplete
        self.refused = refused
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        profile = try box.decodeIfPresent(String.self, forKey: .profile) ?? ""
        scope = try box.decodeIfPresent(String.self, forKey: .scope)
        launchers = try box.decodeIfPresent([DoctorLauncher].self, forKey: .launchers) ?? []
        deleteSecrets = try box.decodeIfPresent([String].self, forKey: .deleteSecrets) ?? []
        keepSecrets = try box.decodeIfPresent([String].self, forKey: .keepSecrets) ?? []
        missingSecrets = try box.decodeIfPresent([String].self, forKey: .missingSecrets) ?? []
        coverageComplete = try box.decodeIfPresent(Bool.self, forKey: .coverageComplete) ?? false
        refused = try box.decodeIfPresent(Bool.self, forKey: .refused) ?? false
        let error = try box.decodeIfPresent(String.self, forKey: .error)
        self.error = error?.isEmpty == true ? nil : error
    }

    public static func parse(_ data: Data) throws -> ProfileRmPlan {
        try JSONDecoder().decode(ProfileRmPlan.self, from: data)
    }

    /// The dry run for `name`.
    public static func arguments(for name: String) -> [String] {
        ["profile", "rm", "--dry-run", "--format", "json", name]
    }
}

public extension ProfileRmPlan {
    /// The dialog for this plan. Removing is always the destructive shape:
    /// Cancel is the default, Return does not remove, Escape cancels. No
    /// button when jit would refuse (something launches it, or it can't
    /// tell): nothing the app could run would delete anything.
    func confirmation(home: String = NSHomeDirectory()) -> DeleteConfirmation {
        if let error {
            return DeleteConfirmation(
                title: "Can't tell whether \(profile) is in use",
                message: "jit could not read everything that might launch it:\n\n\(error)\n\n"
                    + "It won't remove a profile it can't check, so nothing was deleted.",
                button: nil, breaks: false, arguments: []
            )
        }
        if refused || !launchers.isEmpty {
            let lines = launchers.map { "• " + Self.launcherLine($0, home: home) }
            var parts = ["jit won't remove a profile something launches, so nothing was deleted."]
            if !lines.isEmpty {
                parts.append(lines.joined(separator: "\n"))
                parts.append(Self.refusalHint(launchers, home: home))
            }
            return DeleteConfirmation(
                title: "\(profile) is in use", message: parts.joined(separator: "\n\n"), button: nil, breaks: false, arguments: []
            )
        }
        var parts = [coverageComplete
            ? "Nothing jit can see launches \(profile). It can't see scripts or aliases: if one still runs it, that stops working."
            : "jit could not see all of your home folder, so something there may still launch \(profile), "
            + "and it never sees scripts or aliases. Whatever runs it stops working."]
        parts += secretsParts
        let arguments = ["profile", "rm", "--yes", profile]
        parts.append("This runs:\n\njit \(arguments.joined(separator: " "))\n\n" + (deleteSecrets.isEmpty
                ? "Nothing asks again, and no Touch ID: no secret is deleted."
                : "Nothing asks again. Touch ID follows."))
        return DeleteConfirmation(
            title: coverageComplete ? "Remove profile \(profile)?" : "jit can't see everything that might launch \(profile)",
            message: parts.joined(separator: "\n\n"), button: coverageComplete ? "Remove Profile" : "Remove Anyway",
            breaks: true, arguments: arguments, paths: deleteSecrets
        )
    }

    /// What goes, what stays, what was already gone.
    private var secretsParts: [String] {
        let del = deleteSecrets.count
        let keep = keepSecrets.count
        let missing = missingSecrets.count
        var parts: [String] = []
        if del > 0 {
            parts.append((del == 1
                    ? "It deletes the profile and the secret nothing else uses, history and all:\n"
                    : "It deletes the profile and the \(del) secrets nothing else uses, history and all:\n")
                + deleteSecrets.joined(separator: "\n"))
        } else if missing > 0, keep == 0 {
            return [(missing == 1 ? "It deletes the profile; its secret is already gone:\n"
                    : "It deletes the profile; its \(missing) secrets are already gone:\n")
                + missingSecrets.joined(separator: "\n")]
        } else {
            parts.append("It deletes the profile. No secret goes with it.")
        }
        if keep > 0 {
            parts.append((keep == 1 ? "Kept, because something else uses it:\n" : "Kept, because something else uses them:\n")
                + keepSecrets.joined(separator: "\n"))
        }
        if missing > 0 {
            parts.append("Already gone: " + missingSecrets.joined(separator: ", ") + ".")
        }
        return parts
    }

    /// Where a launcher is, as `jit profile rm` says it.
    static func launcherLine(_ launcher: DoctorLauncher, home: String) -> String {
        let file = VaultRmPlan.short(launcher.file, home)
        let detail = launcher.detail ?? ""
        switch launcher.kind {
        case "mcp", "kube": return "\(file) launches it (\(detail))"
        case "aws": return "\(file) \(detail) launches it"
        case "wrap": return "wrapped tool \(detail) launches it"
        case "mount": return "mounted at \(VaultRmPlan.short(detail, home))"
        case "shellrc": return "\(file) exports it (\(detail))"
        case "helper": return "\(file) uses it"
        default: return "\(file) launches it"
        }
    }

    /// The one step that clears the refusal, as jit's hint words it.
    static func refusalHint(_ launchers: [DoctorLauncher], home: String) -> String {
        guard let first = launchers.first else {
            return ""
        }
        if launchers.contains(where: { $0.kind != first.kind }) {
            return "Remove each of those first."
        }
        let one = launchers.count == 1
        let detail = first.detail ?? ""
        switch first.kind {
        case "mcp": return one ? "Remove the \(detail) entry from that file first." : "Remove those entries first."
        case "aws": return one ? "Remove the \(detail) section from that file first." : "Remove those sections first."
        case "kube": return one ? "Remove \(detail) from that file first." : "Remove those users first."
        case "shellrc": return one ? "Remove its jit export line (\(detail)) first." : "Remove those jit export lines first."
        case "wrap": return "jit wrap undo \(detail) unwraps the tool and removes this profile with it."
        case "mount":
            return one ? "jit migrate remove \(VaultRmPlan.short(detail, home)) restores the file and removes the profile with it."
                : "Remove those mounts first."
        case "helper": return "The \(detail) helper may ask for it; undo that migration first."
        default: return "Remove that first."
        }
    }
}
