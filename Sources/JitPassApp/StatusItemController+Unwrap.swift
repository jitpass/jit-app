// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Taking something back out of jit from the Tools window: a wrapped tool
/// (a store wrap's whole family, its login back on disk), or the sealed
/// AWS sign-in. Each is one CLI command after the app's own question.
extension StatusItemController {
    /// `jit wrap undo <tool>`: prompt-free; the dialog exists because the
    /// shim comes out at once and open shells notice on their next call.
    /// No result sheet: the dialog said what happens, and the row turning
    /// Not wrapped says it again. A failure keeps its one-line message.
    /// A store wrap comes out as a family, and its login goes back on disk:
    /// the dialog names both, and the Touch ID jit asks for.
    func unwrapTool(_ tool: String) {
        let alert = NSAlert()
        let record = model.toolListing?.tool(named: tool)
        if let record, record.isStore {
            let family = model.toolListing?.family(of: tool) ?? [tool]
            alert.messageText = "Unwrap " + (family.count > 1 ? NameList.spoken(family) : tool) + "?"
            alert.informativeText = Format.storeUnwrapText(record, family: family)
        } else {
            alert.messageText = "Unwrap \(tool)?"
            alert.informativeText = "\(tool) runs without jit from its next run. Its key stays in the vault."
        }
        alert.addButton(withTitle: "Unwrap")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        runTools(tool, work: { JitCLI.execute(["wrap", "undo", tool]) }, then: { [weak self] _ in
            self?.model.scanStale = true
        })
    }

    /// `jit aws-sso logout`: the sealed AWS sign-in (SSO and `aws login`
    /// sessions) is deleted from the vault and AWS is told to end it. jit asks nothing itself,
    /// so this dialog is the question; Touch ID is jit's, for reading the
    /// login it signs out. No result sheet: the aws row's fact turns to
    /// "signed out of AWS", and a failure keeps jit's line.
    func signOutSSO() {
        let profiles = model.toolListing?.tool(named: "aws")?.ssoProfiles ?? []
        let alert = NSAlert()
        alert.messageText = "Sign out of AWS?"
        alert.informativeText = Format.ssoSignOutText(profiles: profiles)
        alert.addButton(withTitle: "Sign Out")
        alert.addButton(withTitle: "Cancel")
        guard alert.runFrontmost() == .alertFirstButtonReturn else {
            return
        }
        runTools("aws", work: { JitCLI.execute(["aws-sso", "logout"]) }, then: { [weak self] _ in
            self?.vaultChanged()
        })
    }
}
