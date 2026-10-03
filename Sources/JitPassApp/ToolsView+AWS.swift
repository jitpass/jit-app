// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The aws row's sealed sign-in (SSO and `aws login` sessions, jit's
/// aws-sso store): Log In per profile, and Sign Out.
extension ToolsView {
    /// Per profile whenever a sign-in was ever sealed: jit's signed-in is
    /// the whole store, true while any one session is left, so one profile
    /// can need its login while it says so. Logging in is interactive (a
    /// browser, or a pasted code), so it is the terminal's.
    @ViewBuilder
    func awsSignInItems(_ tool: ToolRecord, busy: Bool) -> some View {
        if tool.ssoSignedIn != nil {
            ForEach(tool.ssoProfiles, id: \.self) { profile in
                Button("Log In as \(profile) in Terminal") { actions.mintInTerminal(Format.ssoLoginCommand(profile)) }
                    .disabled(busy)
            }
        }
        if tool.ssoSignedIn == true {
            Button("Sign Out of AWS…", action: actions.signOutSSO).disabled(busy)
        }
    }
}
