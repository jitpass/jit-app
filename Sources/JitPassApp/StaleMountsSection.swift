// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The same spacing tokens the orphans sheet uses.
private enum StaleToken {
    static let sheet: CGFloat = 18
    static let divider: CGFloat = 5
    static let statusRow: CGFloat = 26
}

/// Mount registrations whose project is gone, under the orphaned secrets
/// and apart from them: jit makes this registry edit only inside
/// `vault orphans --prune`, which deletes every orphaned secret in the
/// same pass. So the line above the button says which secrets go with
/// them, and the button says it too.
struct StaleMountsSection: View {
    let orphans: VaultOrphans
    let clear: () -> Void

    var body: some View {
        rows
    }

    @ViewBuilder private var rows: some View {
        Text("Stale mount registrations · \(orphans.staleMounts.count)")
            .font(.system(size: 10, weight: .semibold)).textCase(.uppercase)
            .foregroundStyle(.secondary).padding(.horizontal, StaleToken.sheet).padding(.vertical, StaleToken.divider)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06))
        ForEach(orphans.staleMounts) { mount in
            HStack(spacing: 8) {
                Text(Format.home(mount.mountPath)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("its profile file is gone").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(height: StaleToken.statusRow)
            .padding(.horizontal, StaleToken.sheet)
            Divider()
        }
        HStack {
            Text(orphans.orphans.isEmpty
                ? "Clearing these touches no secret and asks for no Touch ID."
                : "jit clears these only while pruning orphans, so clearing now deletes the \(orphans.orphans.count) "
                + "secret\(orphans.orphans.count == 1 ? "" : "s") above as well.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(clearTitle(orphans), action: clear).controlSize(.small)
        }
        .padding(.horizontal, StaleToken.sheet).padding(.vertical, StaleToken.divider * 2)
    }

    private func clearTitle(_ orphans: VaultOrphans) -> String {
        orphans.orphans.isEmpty ? "Clear…" : "Clear and Delete All…"
    }
}
