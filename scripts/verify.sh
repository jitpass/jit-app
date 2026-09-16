#!/bin/zsh
# Copyright 2026 Meni Tasa
# SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0
#
# Verify a release zip the way a user's Mac will: unpack it, check the
# signature strictly, confirm the team, confirm the stapled ticket, and ask
# Gatekeeper itself. Run against the PUBLISHED asset, never dist/ — the
# lesson of jit's v0.80.0, where the artifact users got was not the one
# that was verified.
#   scripts/verify.sh <zip> <checksums.txt>
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

zip="${1:?release zip}"
sums="${2:?checksums.txt}"
actual=$(shasum -a 256 "$zip" | cut -d' ' -f1)
claimed=$(grep "$(basename "$zip")" "$sums" | cut -d' ' -f1)
[ "$actual" = "$claimed" ] || die "sha256 $actual does not match checksums.txt ($claimed)"

work=$(mktemp -d)
ditto -x -k "$zip" "$work"
app="$work/$APP_NAME.app"
[ -d "$app" ] || die "zip does not contain $APP_NAME.app"
codesign --verify --strict --verbose=2 "$app"
info=$(codesign --display --verbose=2 "$app" 2>&1)
[[ "$info" == *"TeamIdentifier=$TEAM_ID"* ]] || die "not signed by team $TEAM_ID"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
echo "verified: signed by $TEAM_ID, stapled, Gatekeeper-accepted, version $version"
rm -rf "$work"
