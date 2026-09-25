// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Claude Desktop's card in the AI Agents window (the Jobs mockup, frames K
/// and K2). It is an app, not a command line tool, so it has none of a CLI
/// agent's rows about caches and keys: only the rows jit has facts for. Not
/// connected, its one action is Connect (`jit mcp install`); connecting
/// approves nothing, it only opens the door to ask.
extension AgentsView {
    @ViewBuilder var claudeDesktopCard: some View {
        if model.claudeDesktopMCP?.isConnected == true {
            AppCard(
                eyebrow: AgentsBoard.Tier.working.word,
                eyebrowTint: Color(StatusMark.green),
                title: "Claude Desktop",
                note: Format.claudeDesktopNote
            ) {
                EmptyView()
            } rows: {
                AppCardRows {
                    AppRow(name: "Can run", fact: Format.agentCanRun(caller: "Claude", jobs: model.jobs)) {
                        Button("AI Jobs…", action: actions.openAIJobs).buttonStyle(AppButton(kind: .plain))
                    }
                    AppRow(name: "Asks through", fact: Format.claudeDesktopAsksThrough, last: true) {
                        Button("Disconnect…", action: actions.disconnectClaudeDesktop).buttonStyle(AppButton(kind: .plain))
                    }
                }
            }
        } else if model.claudeDesktopMCP != nil {
            AppCard(
                eyebrow: AgentsBoard.Tier.notYet.word,
                eyebrowTint: Color(StatusMark.amber),
                title: "Claude Desktop",
                note: Format.claudeDesktopNotConnectedNote
            ) {
                Button("Connect", action: actions.connectClaudeDesktop).buttonStyle(AppButton(kind: .secondary))
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
