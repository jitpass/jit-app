#!/bin/zsh
# Copyright 2026 Meni Tasa
# SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0
#
# Assemble JitPass.app from a `swift build` product, stamped with the
# version from $VERSION or the tag, with the released jit pinned in
# jit.version inside it (phase 2 of docs/design/menu-bar-app.md): the CLI
# and the service are one binary, placed beside the app executable so the
# cask can symlink it onto PATH, and its shell completions under Resources.
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$config/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$stage/jit" "$APP/Contents/MacOS/jit"
cp -R "$stage/completions" "$APP/Contents/Resources/completions"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :JitVersion $(jit_version)" "$APP/Contents/Info.plist"
echo "built $APP ($config, $version, jit $(jit_version))"
