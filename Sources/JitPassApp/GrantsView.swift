// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Active grants: what each one covers, where it is anchored, when it
/// ends and how often it has served, with Revoke (no authentication, as in
/// the CLI: reducing access is free) and a way to make a new one.
struct GrantsView: View {
    @ObservedObject var model: MenuModel
    let actions: GrantsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.grants.isEmpty ? "No active grants" : model.grantsValue.capitalized).font(.headline)
                Spacer()
                Button("New Grant…", action: actions.newGrant)
                Button("Open in Terminal", action: actions.openInTerminal)
            }
            Text("A grant lets one program use named secrets unattended until a deadline, across screen lock.")
                .font(.subheadline).foregroundStyle(.secondary).padding(.top, 4)
            Divider().padding(.vertical, 8)
            if model.grants.isEmpty {
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.grants) { grant in
                            grantRow(grant)
                        }
                    }
                    .padding(.trailing, 14)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
    }

    private func grantRow(_ grant: GrantStatus) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color(grant.rootAlive ? StatusMark.green : StatusMark.amber)).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(grant.name ?? "pid \(grant.pid)").fontWeight(.semibold)
                    Text("→ " + grant.profiles.joined(separator: ", "))
                }
                Text(Format.grantDetail(grant)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Revoke") { actions.revoke(grant.id) }.buttonStyle(.link)
        }
    }
}

struct GrantsActions {
    var revoke: (String) -> Void = { _ in }
    var newGrant: () -> Void = {}
    var openInTerminal: () -> Void = {}
}
