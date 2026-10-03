// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Store wraps (jit's sealed login stores: gcloud's family, az): a tool
/// that reads its own login store, which the wrap seals in the vault and
/// each run unseals. A family of tools sharing one store is wrapped, and
/// unwrapped, as one.
public extension ToolRecord {
    /// A store wrap: the tool reads its own login store (gcloud's), which
    /// the wrap seals in the vault and each run unseals for that run.
    var isStore: Bool {
        kind == "store"
    }

    /// The name `jit wrap` takes for this tool: a store family is wrapped
    /// by its store's namesake, which wraps every installed member.
    var wrapName: String {
        isStore ? store ?? tool : tool
    }

    /// The store family member that stands for the family where one row
    /// is enough: the tool the store is named after.
    var leadsFamily: Bool {
        !isStore || store == nil || store == tool
    }

    /// The vault paths whose reads are this tool's: what it injects, or
    /// the store it unseals.
    var readPaths: [String] {
        injects.compactMap(\.vaultPath) + (isStore ? [storePath].compactMap { $0 } : [])
    }
}

public extension ToolListing {
    /// Whether a tool needs its own row among the tools not yet through
    /// jit: every tool but a store family's other members, which the
    /// namesake's row covers, since one wrap takes them all. A member
    /// stands alone when its namesake is not installed.
    func standsAlone(_ record: ToolRecord) -> Bool {
        guard record.isStore, !record.leadsFamily, let store = record.store else {
            return true
        }
        return !installed.contains { $0.tool == store }
    }

    /// The installed tools a store wrap takes together: one wrap, and one
    /// undo, covers all of them. Just the tool itself for any other kind.
    func family(of name: String) -> [String] {
        guard let record = tool(named: name), record.isStore, let store = record.store else {
            return [name]
        }
        let members = installed.filter { $0.isStore && $0.store == store }
        // The namesake first: "gcloud, bq and gsutil", never "bq, gcloud".
        let ordered = members.filter(\.leadsFamily) + members.filter { !$0.leadsFamily }
        return ordered.isEmpty ? [name] : ordered.map(\.tool)
    }
}

/// One Log In item on the aws row: the profile, and the command handed
/// to the terminal for it.
public struct SSOLogIn: Sendable, Equatable {
    public var profile: String
    public var command: String
}

public extension ToolRecord {
    /// The aws row's Log In items, one per profile fetching through
    /// `jit aws-sso`, whenever a sign-in was ever sealed: jit's signed-in
    /// is the whole store's, true while any one session is left, so one
    /// profile can need its login while it says so. None when nothing was
    /// ever sealed.
    var ssoLogIns: [SSOLogIn] {
        guard ssoSignedIn != nil else {
            return []
        }
        return ssoProfiles.map { SSOLogIn(profile: $0, command: Self.ssoLoginCommand($0)) }
    }

    /// Logging a sealed AWS profile in again, straight into the vault. The
    /// same for an SSO and an `aws login` profile: jit picks the flow from
    /// the sealed config. Quoted for the terminal's shell, where a name
    /// with a space or a quote would otherwise split.
    static func ssoLoginCommand(_ profile: String) -> String {
        JobDraft.join(["jit", "aws-sso", "login", "--profile", profile])
    }
}
