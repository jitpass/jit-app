// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// An AI app's card in the AI Agents window (the Jobs mockup, frames K and
/// K2): Claude Desktop, and Cursor on the same card. An app is not a command
/// line tool, so it has none of a CLI agent's rows about caches and keys:
/// only the rows jit has facts for. Not connected, its one action is Connect
/// (`jit mcp install`); connecting approves nothing, it only opens the door
/// to ask.
extension AgentsView {
    @ViewBuilder func appCard(_ app: MCPApp) -> some View {
        let status = model.mcpStatus[app.id]
        if status?.isConnected == true {
            AppCard(
                eyebrow: AgentsBoard.Tier.working.word,
                eyebrowTint: Color(StatusMark.green),
                title: app.name,
                note: Format.appNote(app)
            ) {
                EmptyView()
            } rows: {
                AppCardRows {
                    AppRow(name: "Can run", fact: Format.agentCanRun(caller: app.caller, jobs: model.jobs)) {
                        Button("AI Jobs…", action: actions.openAIJobs).buttonStyle(AppButton(kind: .plain))
                    }
                    AppRow(name: "Asks through", fact: Format.appAsksThrough(app), last: true) {
                        Button("Disconnect…") { actions.disconnectApp(app) }.buttonStyle(AppButton(kind: .plain))
                    }
                }
            }
        } else if status != nil {
            AppCard(
                eyebrow: AgentsBoard.Tier.notYet.word,
                eyebrowTint: Color(StatusMark.amber),
                title: app.name,
                note: Format.appNotConnectedNote(app)
            ) {
                Button("Connect") { actions.connectApp(app) }.buttonStyle(AppButton(kind: .secondary))
            } rows: {
                AppCardRows {
                    AppRow(name: "Can run", fact: "Nothing. It isn't connected", last: true) {
                        EmptyView()
                    }
                }
            }
        }
    }
}
