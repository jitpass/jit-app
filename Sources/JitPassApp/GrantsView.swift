// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Grants: the small window (one purpose, nothing to filter), built from
/// the window system. A header that counts, one card per grant with its
/// state on the eyebrow, and New Grant as this window's sheet. Revoke asks
/// once, because a standing grant's revoke deletes a key; nothing here
/// opens a terminal, and the banner reports what happened.
struct GrantsView: View {
    @ObservedObject var model: MenuModel
    let actions: GrantsActions
    let sheetActions: GrantActions

    var body: some View {
        VStack(spacing: 0) {
            // Measured with the banner, which wraps when jit's note is long.
            VStack(spacing: 0) {
                if let banner = model.grantBanner {
                    WindowBanner(tint: Color(model.grantBannerFailed ? StatusMark.red : StatusMark.green), text: banner, wraps: true)
                }
                header
                content
            }
            .measureWindowHeight()
        }
        .frame(
            minWidth: Win.widthSmall, maxWidth: .infinity,
            minHeight: Win.minimum(Win.heightSmall), maxHeight: .infinity,
            alignment: .top
        )
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onPreferenceChange(WindowHeightKey.self) { height in
            actions.fit(height)
        }
        .sheet(isPresented: $model.grantSheet) {
            GrantSheetView(model: model, actions: sheetActions)
        }
        .onAppear(perform: actions.reload)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Win.s5) {
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(Format.grantsHeadline(model.grants)).font(Win.head)
                Text(Format.grantsSubline(model.grants)).font(Win.sub).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Win.s5)
            Button("New Grant…", action: actions.newGrant).buttonStyle(AppButton(kind: .primary))
        }
        .windowRegion(rule: !model.grants.isEmpty)
    }

    @ViewBuilder private var content: some View {
        if model.grants.isEmpty {
            WindowEmptyState(tint: Color(StatusMark.green), title: Format.grantsEmptyTitle, message: Format.grantsEmptyMessage) {
                EmptyView()
            }
        } else {
            ScrollView {
                VStack(spacing: Win.s5) {
                    ForEach(model.grants) { grant in
                        GrantCard(grant: grant, actions: actions)
                    }
                }
                .padding(Win.s6)
            }
        }
    }
}

/// One grant: its tier on the eyebrow, the rotated-secret question when
/// there is one, then its row and, under it, each rotated secret.
struct GrantCard: View {
    let grant: GrantStatus
    let actions: GrantsActions

    var body: some View {
        let tier = Format.grantTier(grant)
        VStack(alignment: .leading, spacing: Win.s4) {
            HStack(spacing: Win.s3) {
                StateDot(tint: tint(tier))
                Text(Format.grantEyebrow(tier)).font(Win.eyebrow).foregroundStyle(.secondary)
            }
            if tier == .needsYou {
                HStack(alignment: .top, spacing: Win.s5) {
                    VStack(alignment: .leading, spacing: Win.s1) {
                        Text(Format.rotatedTitle(grant)).font(Win.cardTitle)
                        Text(Format.rotatedNote(grant)).font(Win.cardNote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Win.s5)
                    Button("Re-approve…") { actions.reapprove(grant) }.buttonStyle(AppButton(kind: .secondary))
                }
            }
            AppCardRows {
                AppRow(
                    name: Format.grantName(grant), detail: Format.grantProfiles(grant),
                    fact: Format.grantFact(grant), last: grant.rotatedSecrets.isEmpty
                ) {
                    Button("Revoke…") { actions.revoke(grant) }.buttonStyle(AppButton(kind: .quiet))
                }
                ForEach(Array(grant.rotatedSecrets.enumerated()), id: \.element) { index, secret in
                    GrantSecretRow(secret: secret, last: index == grant.rotatedSecrets.count - 1)
                }
            }
        }
        .padding(Win.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
    }

    private func tint(_ tier: Format.GrantTier) -> Color {
        switch tier {
        case .serving: Color(StatusMark.green)
        case .needsYou, .ending: Color(StatusMark.amber)
        case .standing, .active: Design.Label.secondary
        }
    }
}

/// A secret inside the grant above it: the name in mono, the chip that
/// carries the news, and the one fact. No actions of its own.
struct GrantSecretRow: View {
    let secret: String
    var last = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Win.s1) {
                HStack(spacing: Win.s3) {
                    Text(secret).font(Win.command).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Text("rotated").font(Win.eyebrow).foregroundStyle(.secondary)
                        .padding(.horizontal, Win.s3).padding(.vertical, 1)
                        .background(Design.Surface.field, in: RoundedRectangle(cornerRadius: Design.Radius.box, style: .continuous))
                }
                Text(Format.rotatedFact).font(Win.rowFact).foregroundStyle(.secondary)
            }
            .padding(.vertical, Win.s4)
            .padding(.horizontal, Win.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !last {
                Rectangle().fill(WindowSurface.rowLine).frame(height: 1)
            }
        }
    }
}

struct GrantsActions {
    var reload: () -> Void = {}
    var newGrant: () -> Void = {}
    var revoke: (GrantStatus) -> Void = { _ in }
    var reapprove: (GrantStatus) -> Void = { _ in }
    var fit: (CGFloat) -> Void = { _ in }
}
