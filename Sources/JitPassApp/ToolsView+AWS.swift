// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The aws row's sealed sign-in (SSO and `aws login` sessions, jit's
/// aws-sso store): Log In per profile, and Sign Out.
extension ToolsView {
    /// Log In per profile (`ToolRecord.ssoLogIns`); logging in is
    /// interactive (a browser, or a pasted code), so it is the terminal's.
    @ViewBuilder
    func awsSignInItems(_ tool: ToolRecord, busy: Bool) -> some View {
        ForEach(tool.ssoLogIns, id: \.profile) { login in
            Button("Log In as \(login.profile) in Terminal") { actions.mintInTerminal(login.command) }
                .disabled(busy)
        }
        if tool.ssoSignedIn == true {
            Button("Sign Out of AWS…", action: actions.signOutSSO).disabled(busy)
        }
    }
}
