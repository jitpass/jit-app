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
        cli?.vault.map { "\($0.secretsStored) secrets" }
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
