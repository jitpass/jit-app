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

# Inside out, never --deep: the helper first, then the app that seals it.
# Signing the helper replaces the signature jit's own release gave the
# binary, so the hardened runtime is passed again here; fetch-jit.sh has
# already verified that release signature on the staged copy.
#
# The helper carries the Secure Enclave entitlement (Resources/
# Agent.entitlements). It is restricted: without a provisioning profile that
# authorizes it, for this app ID and this exact certificate, macOS kills the
# helper at launch, and with it every user's jit service. So the profile is
# checked against the identity BEFORE anything is signed.
check_agent_profile "$AGENT_PROFILE" "$identity"
cp "$AGENT_PROFILE" "$HELPER/Contents/embedded.provisionprofile"
codesign --force --sign "$identity" --options runtime --timestamp \
  --entitlements Resources/Agent.entitlements \
  --identifier "$HELPER_CODE_ID" "$HELPER"
codesign --verify --strict --verbose=2 "$HELPER"
helperinfo=$(codesign --display --verbose=2 "$HELPER" 2>&1)
[[ "$helperinfo" == *"TeamIdentifier=$TEAM_ID"* ]] || die "helper signed, but not by team $TEAM_ID"
[[ "$helperinfo" == *"(runtime)"* ]] || die "helper signed without the hardened runtime"
[[ "$helperinfo" == *$'\n'"Identifier=$HELPER_CODE_ID"$'\n'* ]] || die "helper's code identifier is not $HELPER_CODE_ID (see HELPER_CODE_ID in lib.sh)"
helperents=$(codesign --display --entitlements - --xml "$HELPER" 2>/dev/null)
[[ "$helperents" == *"$HELPER_GROUP"* && "$helperents" == *"$TEAM_ID.$HELPER_ID"* ]] || die "helper signed without the Secure Enclave entitlement"
# The launch AMFI performs is the real test of entitlement + profile +
# certificate; a mismatch dies here with exit 137 rather than on a user's Mac.
"$HELPER/Contents/MacOS/jit" --version > /dev/null || die "the signed helper does not launch: its profile and entitlements disagree"

codesign --force --sign "$identity" --options runtime --timestamp \
  --entitlements Resources/JitPass.entitlements "$APP"
codesign --verify --strict --verbose=2 "$APP"
# Captured, not piped into grep -q: under pipefail a quitting grep breaks
# codesign's pipe and the check fails on a perfectly good signature.
info=$(codesign --display --verbose=2 "$APP" 2>&1)
[[ "$info" == *"TeamIdentifier=$TEAM_ID"* ]] || die "signed, but not by team $TEAM_ID"
echo "signed $APP as team $TEAM_ID"
