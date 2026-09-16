#!/bin/zsh
# Copyright 2026 Meni Tasa
# SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0
#
# Assemble JitPass.app from a `swift build` product. Phase 1 bundles only the
# Swift executable; phase 2 of docs/design/menu-bar-app.md adds the jit and
# jit-agent binaries under Contents/Helpers. Signing is a separate step
# (scripts/sign.sh, once the identity is wired) so an unsigned local build
# never looks like a release.
set -euo pipefail
cd "$(dirname "$0")/.."
config="${1:-release}"
swift build -c "$config" --product JitPass
out="dist/JitPass.app"
rm -rf "$out"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources" "$out/Contents/Helpers"
cp ".build/$config/JitPass" "$out/Contents/MacOS/JitPass"
cp Resources/Info.plist "$out/Contents/Info.plist"
echo "built $out ($config)"
