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

# The bundled jit is what `brew install jitpass` puts on PATH, so it is
# verified the way jit's own release gate verifies a tarball: signed by the
# team, and reporting the version the bundle claims to carry.
helper="$app/Contents/Helpers/$HELPER_NAME.app"
jit="$app/$HELPER_JIT_REL"
[ -x "$jit" ] || die "bundle carries no executable jit in $HELPER_NAME.app"
codesign --verify --strict --verbose=2 "$helper"
helperid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$helper/Contents/Info.plist")
[ "$helperid" = "$HELPER_ID" ] || die "helper bundle is $helperid, want $HELPER_ID"
helperinfo=$(codesign --display --verbose=2 "$helper" 2>&1)
[[ "$helperinfo" == *"(runtime)"* ]] || die "helper lacks the hardened runtime"
# The old path every installed plist and PATH link names must still lead here.
compat="$app/Contents/MacOS/jit"
[ -L "$compat" ] || die "Contents/MacOS/jit is not the compat symlink"
[ "$(cd "$(dirname "$compat")" && realpath "$(readlink "$compat")")" = "$(realpath "$jit")" ] \
  || die "Contents/MacOS/jit does not resolve to the helper's jit"
jitinfo=$(codesign --display --verbose=2 "$jit" 2>&1)
[[ "$jitinfo" == *"TeamIdentifier=$TEAM_ID"* ]] || die "bundled jit is not signed by team $TEAM_ID"
want=$(/usr/libexec/PlistBuddy -c "Print :JitVersion" "$app/Contents/Info.plist")
got=$("$jit" --version)
[[ "$got" == *"$want"* ]] || die "bundled jit reports '$got', bundle claims $want"
[ -f "$app/Contents/Resources/completions/_jit" ] || die "bundle carries no shell completions"
echo "verified: signed by $TEAM_ID, stapled, Gatekeeper-accepted, version $version, jit $want"
rm -rf "$work"
