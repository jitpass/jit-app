// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The Remove JitPass window's pure half (docs/design/offboarding.md): the
/// plan `jit uninstall --restore --dry-run --format json` prints, the events
/// `--format ndjson` streams, and the checklist they drive. No AppKit and no
/// process, so all of it is unit-tested.
public enum OffboardingStep: Equatable, Sendable {
    case loading
    /// The plan could not be read; the window says why and offers nothing else.
    case unavailable(String)
    case plan
    /// Shown only when some secrets have no file to go back to.
    case recovery
    case removing
    /// A file could not be put back, so jit deleted nothing.
    case couldNotRestore
    case done
}

/// One file Remove puts back.
public struct UninstallPlanItem: Decodable, Equatable, Sendable, Identifiable {
    public let path: String
    public let kind: String
    /// Changed since jit rewrote it: today's version is kept beside it.
    public let drifted: Bool

    public var id: String {
        path
    }

    enum CodingKeys: String, CodingKey {
        case path, kind, drifted
    }

    public init(path: String, kind: String, drifted: Bool = false) {
        self.path = path
        self.kind = kind
        self.drifted = drifted
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        path = try box.decode(String.self, forKey: .path)
        kind = try box.decode(String.self, forKey: .kind)
        drifted = try box.decodeIfPresent(Bool.self, forKey: .drifted) ?? false
    }
}

/// A secret no restored file will hold.
public struct UninstallPlanSecret: Decodable, Equatable, Sendable, Identifiable {
    public let path: String
    public let secretClass: String?

    public var id: String {
        path
    }

    enum CodingKeys: String, CodingKey {
        case path
        case secretClass = "class"
    }

    public init(path: String, secretClass: String? = nil) {
        self.path = path
        self.secretClass = secretClass
    }
}

/// What Remove will do, as jit reports it before anything changes.
public struct UninstallPlan: Decodable, Equatable, Sendable {
    public typealias Item = UninstallPlanItem
    public typealias Secret = UninstallPlanSecret

    public var restore: [Item] = []
    /// Shell history and AI caches: left cleaned.
    public var keptClean: [String] = []
    /// Shell configs the user already took jit's line out of.
    public var unwired: [String] = []
    /// Migrated files that no longer exist; not recreated.
    public var gone: [String] = []
    /// Secrets no restored file will hold. Remove loses them.
    public var vaultOnly: [Secret] = []
    public var projectStores: [String] = []
    public var secrets = 0
    /// False when the vault's key is missing: nothing can be put back.
    public var keyPresent = true
    public var shims: [String] = []
    public var historyGuard = false
    public var helpers: [String] = []
    public var pathLineFile: String?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case restorePlan = "restore_plan"
        case secrets
        case keyPresent = "key_present"
        case shims
        case historyGuard = "guard"
        case helpers
        case pathLineFile = "path_line_file"
    }

    enum RestoreKeys: String, CodingKey {
        case restore
        case keptClean = "kept_clean"
        case unwired, gone
        case vaultOnly = "vault_only"
        case projectStores = "project_stores"
    }

    /// Go prints a nil slice as null, so every list is optional on the wire.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        secrets = try box.decodeIfPresent(Int.self, forKey: .secrets) ?? 0
        keyPresent = try box.decodeIfPresent(Bool.self, forKey: .keyPresent) ?? true
        shims = try box.decodeIfPresent([String].self, forKey: .shims) ?? []
        historyGuard = try box.decodeIfPresent(Bool.self, forKey: .historyGuard) ?? false
        helpers = try box.decodeIfPresent([String].self, forKey: .helpers) ?? []
        pathLineFile = try box.decodeIfPresent(String.self, forKey: .pathLineFile)
        let plan = try box.nestedContainer(keyedBy: RestoreKeys.self, forKey: .restorePlan)
        restore = try plan.decodeIfPresent([Item].self, forKey: .restore) ?? []
        keptClean = try plan.decodeIfPresent([String].self, forKey: .keptClean) ?? []
        unwired = try plan.decodeIfPresent([String].self, forKey: .unwired) ?? []
        gone = try plan.decodeIfPresent([String].self, forKey: .gone) ?? []
        vaultOnly = try plan.decodeIfPresent([Secret].self, forKey: .vaultOnly) ?? []
        projectStores = try plan.decodeIfPresent([String].self, forKey: .projectStores) ?? []
    }

    public static func parse(_ data: Data) throws -> UninstallPlan {
        try JSONDecoder().decode(UninstallPlan.self, from: data)
    }

    public var drifted: [Item] {
        restore.filter(\.drifted)
    }
}

/// One file that could not be put back, and why.
public struct UninstallFailure: Decodable, Equatable, Sendable, Identifiable {
    public let path: String
    public let error: String

    public var id: String {
        path
    }

    public init(path: String, error: String) {
        self.path = path
        self.error = error
    }
}

/// One line of `jit uninstall --format ndjson`.
public enum UninstallEvent: Equatable, Sendable {
    public typealias Failure = UninstallFailure

    /// A step began; the one before it ended.
    case step(String)
    case file(path: String, error: String?)
    /// Files could not be put back; jit deleted nothing.
    case failed([Failure])
    case done(problems: [String])

    private struct Wire: Decodable {
        let event: String
        let step: String?
        let path: String?
        let error: String?
        let failures: [Failure]?
        let problems: [String]?
    }

    /// nil for a line that is not an event this build knows: a newer jit
    /// may say more, and an unknown line must never stop the run.
    public static func parse(line: String) -> UninstallEvent? {
        guard let data = line.data(using: .utf8), let wire = try? JSONDecoder().decode(Wire.self, from: data) else {
            return nil
        }
        switch wire.event {
        case "step": return wire.step.map(UninstallEvent.step)
        case "file": return wire.path.map { .file(path: $0, error: wire.error) }
        case "failed": return .failed(wire.failures ?? [])
        case "done": return .done(problems: wire.problems ?? [])
        default: return nil
        }
    }
}

public enum OffboardingPlan {
    /// The arguments for the whole way out, and for the one path that
    /// deletes without restoring (a vault whose key is gone).
    public static let restoreCommand = ["uninstall", "--restore", "--yes", "--format", "ndjson"]
    public static let purgeCommand = ["uninstall", "--purge", "--yes", "--format", "ndjson"]
    public static let planCommand = ["uninstall", "--restore", "--dry-run", "--format", "json"]

    /// The row that does the app's own part, after jit has finished.
    public static let appStep = "app"

    /// Which checklist row each engine step belongs to. Stopping the
    /// service and unwrapping the tools read as one thing to a person.
    static let rowForStep = [
        "auth": "auth", "restore": "restore", "stores": "stores",
        "service": "tools", "tools": "tools", "vault": "vault", appStep: appStep
    ]

    /// The checklist, in the order jit works: files first, deletions last.
    public static func tasks(plan: UninstallPlan, restoring: Bool) -> [OnboardingTask] {
        var rows: [OnboardingTask] = [
            row("auth", "Touch ID", "One fingerprint covers everything below.")
        ]
        if restoring {
            let count = plan.restore.count
            rows.append(row(
                "restore", count == 1 ? "Put 1 file back" : "Put \(count) files back",
                "Each holds its secrets as plain text again. Nothing is deleted until all of them are in place."
            ))
            if !plan.projectStores.isEmpty {
                let stores = plan.projectStores.count
                rows.append(row(
                    "stores", stores == 1 ? "Remove .jit from 1 project folder" : "Remove .jit from \(stores) project folders",
                    "The profiles JitPass kept beside your code."
                ))
            }
        }
        rows.append(row("tools", toolsTitle(plan.shims), "They go back to their own sign-in."))
        rows.append(row("vault", "Delete the vault and its key", vaultDetail(plan)))
        rows.append(row(appStep, "Remove settings and permissions", "Open at login, notifications, the jit command, preferences."))
        return rows
    }

    /// The checklist after one event. Rows before the named one are done;
    /// a failed restore marks its row and leaves the rest untouched.
    public static func advance(_ tasks: [OnboardingTask], with event: UninstallEvent) -> [OnboardingTask] {
        var rows = tasks
        switch event {
        case let .step(step):
            guard let id = rowForStep[step], let index = rows.firstIndex(where: { $0.id == id }) else {
                return rows
            }
            for earlier in rows.indices where earlier < index {
                rows[earlier].state = .done
            }
            if rows[index].state != .done {
                rows[index].state = .running
            }
        case let .failed(failures):
            if let index = rows.firstIndex(where: { $0.id == "restore" }) {
                let count = failures.count
                rows[index].state = .failed(count == 1 ? "1 file could not be put back." : "\(count) files could not be put back.")
            }
        case .done:
            for index in rows.indices where rows[index].id != appStep {
                rows[index].state = .done
            }
        case .file:
            break
        }
        return rows
    }

    /// "2 you added by hand, 4 sign-ins JitPass captured": what the
    /// vault-only secrets are, in a person's words.
    public static func describe(vaultOnly: [UninstallPlan.Secret]) -> String {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for secret in vaultOnly {
            let words = words(forClass: secret.secretClass)
            if counts[words] == nil {
                order.append(words)
            }
            counts[words, default: 0] += 1
        }
        return order.map { "\(counts[$0] ?? 0) \($0)" }.joined(separator: ", ")
    }

    private static func words(forClass secretClass: String?) -> String {
        switch secretClass {
        case "manual": "added by hand"
        case "wrap": "from protected tools"
        case "shell_history": "found in shell history"
        case nil, "": "from older setups"
        default: "whose file is gone"
        }
    }

    private static func row(_ id: String, _ title: String, _ detail: String) -> OnboardingTask {
        OnboardingTask(kind: .remove(id), title: title, detail: detail, command: nil)
    }

    private static func toolsTitle(_ shims: [String]) -> String {
        switch shims.count {
        case 0: "Stop the background service"
        case 1: "Stop the service, unprotect \(shims[0])"
        case 2: "Stop the service, unprotect \(shims[0]) and \(shims[1])"
        default: "Stop the service, unprotect \(shims.count) tools"
        }
    }

    private static func vaultDetail(_ plan: UninstallPlan) -> String {
        var parts = ["From this Mac and from your login keychain."]
        if plan.historyGuard || plan.pathLineFile != nil {
            parts.append("JitPass's lines leave your shell config; nothing else in it changes.")
        }
        return parts.joined(separator: " ")
    }
}
