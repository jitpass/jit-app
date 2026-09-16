#!/bin/zsh
# Copyright 2026 Meni Tasa
# SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0
#
# Submit the signed bundle to Apple, wait for the verdict, staple the ticket
# and produce the release zip plus checksums. Unlike jit's bare Mach-O, an
# .app CAN be stapled, so the cask works without an online ticket fetch.
#
# Waits for the verdict rather than fire-and-forget, for the reason in
# jit's spike/notarize-e2e/FINDINGS.md: an unverified submission once
# shipped. The 15 minute cap matches jit's; healthy verdicts take seconds.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

: "${NOTARY_KEY_FILE:?path to the App Store Connect API .p8}"
: "${NOTARY_KEY_ID:?}"
: "${NOTARY_ISSUER_ID:?}"
[ -d "$APP" ] || die "no $APP; run scripts/bundle.sh and scripts/sign.sh first"
codesign --verify --strict "$APP" || die "bundle is not signed; run scripts/sign.sh"

submission="$DIST/$APP_NAME-submission.zip"
ditto -c -k --keepParent "$APP" "$submission"
xcrun notarytool submit "$submission" --wait --timeout 15m \
  --key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
rm -f "$submission"

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

zip="$DIST/$(artifact_name)"
rm -f "$zip"
ditto -c -k --keepParent "$APP" "$zip"
(cd "$DIST" && shasum -a 256 "$(artifact_name)" > checksums.txt)
echo "notarized, stapled and packed: $zip"
cat "$DIST/checksums.txt"
