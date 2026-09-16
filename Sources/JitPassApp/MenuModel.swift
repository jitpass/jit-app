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
    @Published var consentEnabled: Bool?
    @Published var cli: CLIStatus?
    @Published var scan: ScanReport?
    @Published var scanning = false
    @Published var scanError: String?
    /// The folder the last scan was limited to; nil means the whole Mac.
    @Published var scanScope: String?
    @Published var audit: AuditReport?
    @Published var auditFilter = AuditFilter(since: "24h")
    @Published var auditLoading = false
    @Published var grantProcesses: [RunningProcess] = []
    @Published var grantProfiles: [String] = []
    @Published var grantBusy = false
    @Published var grantError: String?

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

    var exposureValue: String {
        if scanning {
            return "scanning…"
        }
        guard let s = scan?.summary else {
            return "not scanned yet"
        }
        return "\(s.exposureScore) / 100 · \(s.riskLevel)"
    }
}
