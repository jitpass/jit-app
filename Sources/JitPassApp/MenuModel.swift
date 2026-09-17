// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Everything the panel shows, as plain values the controller writes and the
/// view reads. No socket, no process, no AppKit: the view stays a pure
/// rendering of this, and the controller stays the only place that talks to
/// jit.
@MainActor
final class MenuModel: ObservableObject {
    @Published var state: SessionState = .notRunning
    @Published var grants: [GrantStatus] = []
    @Published var lastEvent: SessionEvent?
    /// Disclosed challenges the agent has parked with this app, oldest
    /// first; the consent sheet shows the first.
    @Published var consentRequests: [ConsentRequest] = []
    @Published var consentEnabled: Bool?
    @Published var ttlSeconds: Int64?
    @Published var cli: CLIStatus?
    @Published var scan: ScanReport?
    @Published var scanning = false
    @Published var scanError: String?
    /// The folder the last scan was limited to; nil means the whole Mac.
    @Published var scanScope: String?
    /// The last whole-Mac scan, whoever started it: what the Protected row
    /// shows. A folder scan never replaces it.
    @Published var macScan: ScanReport?
    @Published var macScanAt: Date?
    /// Set when jit changed something (a Protect ran) so the next chance
    /// rescans even before the schedule says so.
    @Published var scanStale = false
    @Published var scanSchedule: ScanSchedule = .init(
        rawValue: UserDefaults.standard.string(forKey: ScanSchedule.preferenceKey) ?? ""
    ) ?? .default
    @Published var scanExcludes: [String] = ScanExcludes.load()
    @Published var audit: AuditReport?
    @Published var auditFilter = AuditFilter(since: "24h")
    @Published var auditLoading = false
    @Published var grantProcesses: [RunningProcess] = []
    @Published var grantSessionRoots: [RunningProcess] = []
    @Published var grantProfiles: [String] = []
    /// Profiles doctor reports as broken, with why; never offered.
    @Published var brokenProfiles: [String: String] = [:]
    @Published var grantBusy = false
    @Published var grantError: String?
    @Published var doctor: DoctorReport?
    @Published var doctorAt: Date?
    @Published var doctorRunning = false
    /// Why the last in-app doctor action failed, if it did.
    @Published var doctorMessage: String?
    /// Whether macOS has granted the app Full Disk Access, checked when the scan window opens.
    @Published var fullDiskAccess = false
    /// The vault as `jit vault list` reports it: paths and headers, never a
    /// value. Reloaded after every vault operation.
    @Published var vaultListing: VaultListing?
    @Published var vaultHistory: VaultHistory?
    /// The path (or action) a vault command is running for; one at a time,
    /// because most of them put a Touch ID prompt on screen.
    @Published var vaultBusy: String?
    /// Why the last vault operation failed, under the header until the next one.
    @Published var vaultMessage: String?
    /// A one-line confirmation ("copied, clears in 45s") that clears itself.
    @Published var vaultNotice: String?
    @Published var vaultSheet: VaultSheet?
    /// The one value on screen, while it is. The String here is the copy the
    /// app cannot wipe (see docs/design/vault-window.md §3a); it exists for
    /// the countdown and is dropped with the reveal. The bytes behind it are
    /// a `SecretBuffer` the controller owns and wipes.
    @Published var vaultReveal: VaultReveal?
    @Published var settingsBusy = false
    @Published var settingsMessage: String?
    @Published var launchAtLogin = false
    @Published var terminalApp = ""
    /// The bundle identifier of the editor scan rows open files with; "" is the system default.
    @Published var editorApp = ""
    @Published var editors: [Editor.Choice] = []

    var serviceValue: String {
        switch state {
        case .notRunning: "Not running"
        case .locked: "Running · locked"
        case .unlocked: "Running · unlocked"
        }
    }

    var grantsValue: String {
        switch grants.count {
        case 0: "none"
        case 1: "1 active"
        default: "\(grants.count) active"
        }
    }

    var vaultValue: String? {
        if let listing = vaultListing {
            let linked = listing.linkedCount
            return "\(listing.secrets.count) secrets" + (linked > 0 ? " · \(linked) linked" : "")
        }
        return cli?.vault.map { "\($0.secretsStored) secrets" }
    }

    var mountsValue: String? {
        cli?.mounts.map { "\($0.registered) " + ($0.servingReal ? "serving real values" : "serving decoys") }
    }

    var consentValue: String? {
        consentEnabled.map { $0 ? "On" : "Off" }
    }

    /// The last verdict stays on screen while a recheck runs; "checking…"
    /// appears only before the first result exists.
    var doctorValue: String {
        if let doctor {
            return doctor.verdict
        }
        return doctorRunning ? "checking…" : "not checked"
    }

    var vaultSummary: String {
        guard let listing = vaultListing else {
            return vaultValue ?? "not read yet"
        }
        var parts = ["\(listing.secrets.count) secret" + (listing.secrets.count == 1 ? "" : "s")]
        if listing.linkedCount > 0 {
            parts.append("\(listing.linkedCount) linked")
        }
        if !listing.backups.isEmpty {
            parts.append("\(listing.backups.count) backups")
        }
        return parts.joined(separator: " · ")
    }

    /// The CLI's headline: secrets protected over secrets known, for the
    /// whole Mac. Never a folder's number.
    var protectedValue: String {
        if let s = macScan?.summary {
            return "\(s.secretsProtected) of \(s.secretsTotal) · \(s.percent)%"
        }
        if scanning {
            return "scanning…"
        }
        if scanSchedule != .off, !fullDiskAccess {
            return "needs Full Disk Access"
        }
        return "not scanned yet"
    }
}

/// The sheet the Vault window has open, if any.
enum VaultSheet: Identifiable, Equatable {
    /// Add a secret; with `replacing`, the path is fixed and the current
    /// value goes to history.
    case add(group: String?, replacing: String?)
    case link(group: String?, replacing: String?)
    case history(path: String)

    var id: String {
        switch self {
        case let .add(group, replacing): "add:\(group ?? ""):\(replacing ?? "")"
        case let .link(group, replacing): "link:\(group ?? ""):\(replacing ?? "")"
        case let .history(path): "history:\(path)"
        }
    }
}

/// A value on screen: which row, the text, and seconds left.
struct VaultReveal: Equatable {
    var path: String
    var text: String
    var secondsLeft: Int
}
