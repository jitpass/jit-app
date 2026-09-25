#!/bin/zsh
# Copyright 2026 Meni Tasa
# SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0
#
# Assemble JitPass.app from a `swift build` product, stamped with the
# version from $VERSION or the tag, with the released jit pinned in
# jit.version inside it (phase 2 of docs/design/menu-bar-app.md): the CLI
# and the service are one binary, the main executable of its own helper
# bundle (Contents/Helpers/JitPassAgent.app) so a provisioning profile can
# authorize it, with Contents/MacOS/jit kept as a symlink into it for every
# launchd plist and PATH link that names the old place. Shell completions go
# under Resources.
# Signing is scripts/sign.sh, deliberately separate, so an unsigned local
# build never looks like a release.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
config="${1:-release}"
version="$(version_from_env)"

swift build -c "$config" --product "$APP_NAME"
scripts/fetch-jit.sh
stage="$(jit_stage)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$HELPER/Contents/MacOS"
cp ".build/$config/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$stage/jit" "$HELPER/Contents/MacOS/jit"
cp Resources/Agent-Info.plist "$HELPER/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$HELPER/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$HELPER/Contents/Info.plist"
# Relative, so it survives the app being moved or translocated.
ln -s "../Helpers/$HELPER_NAME.app/Contents/MacOS/jit" "$APP/Contents/MacOS/jit"
cp -R "$stage/completions" "$APP/Contents/Resources/completions"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :JitVersion $(jit_version)" "$APP/Contents/Info.plist"
echo "built $APP ($config, $version, jit $(jit_version))"
