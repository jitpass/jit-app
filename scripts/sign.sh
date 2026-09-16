#!/bin/zsh
# Copyright 2026 Meni Tasa
# SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0
#
# Developer ID sign the bundle with the hardened runtime and the app's
# entitlements. The identity is chosen by TEAM ID, never by name: this
# machine's keychain also holds an unrelated Apple Development identity, and
# picking "the first Developer ID" is how a release gets signed by the wrong
# team. $SIGN_KEYCHAIN narrows the search to CI's temporary keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

[ -d "$APP" ] || die "no $APP; run scripts/bundle.sh first"
identity=$(security find-identity -v -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} \
  | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 | awk '{print $2}')
[ -n "$identity" ] || die "no Developer ID Application identity for team $TEAM_ID in the keychain"

codesign --force --sign "$identity" --options runtime --timestamp \
  --entitlements Resources/JitPass.entitlements "$APP"
codesign --verify --strict --verbose=2 "$APP"
# Captured, not piped into grep -q: under pipefail a quitting grep breaks
# codesign's pipe and the check fails on a perfectly good signature.
info=$(codesign --display --verbose=2 "$APP" 2>&1)
[[ "$info" == *"TeamIdentifier=$TEAM_ID"* ]] || die "signed, but not by team $TEAM_ID"
echo "signed $APP as team $TEAM_ID"
