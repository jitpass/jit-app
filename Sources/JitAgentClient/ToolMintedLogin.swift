// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// jit's `tool_minted` on a finding: the login's name ("A kubelogin OIDC
/// login (renews itself)") and its advice, which may quote commands in
/// backticks.
public struct ToolMintedLogin: Codable, Sendable, Equatable {
    public var title: String
    public var advice: String

    public init(title: String, advice: String) {
        self.title = title
        self.advice = advice
    }
}

public extension ScanReport {
    /// Logins a tool renews itself: nothing for the reader to rotate, and
    /// outside the summary's counts, so never a Needs-you row.
    var selfRenewing: [ScanFinding] {
        findings.filter { $0.toolMinted != nil && !$0.scaffolding }
    }
}
