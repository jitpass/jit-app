#!/bin/zsh
# Copyright 2026 Meni Tasa
# SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0
#
# The local gate, the same steps CI runs, failing on the first one that
# fails. Chaining these by hand through grep once swallowed a build failure
# and pushed a commit that did not compile; this script exists so that the
# only way to build for a commit is the way that cannot hide a failure.
#   scripts/gate.sh            format, lint, build, test
#   scripts/gate.sh --run      also bundle and relaunch the dev build
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swiftformat . > /dev/null
swiftformat --lint . > /dev/null
swiftlint --strict --quiet
log=$(mktemp)
swift build -c release > "$log" 2>&1 || { grep -E 'error:' "$log" || cat "$log"; exit 1; }
swift test > "$log" 2>&1 || { grep -E 'error:|failed' "$log" || cat "$log"; exit 1; }
grep -E 'Executed [0-9]+ tests' "$log" | tail -1
rm -f "$log"
echo "gate: green"

if [ "${1:-}" = "--run" ]; then
  pkill -x JitPass 2> /dev/null || true
  sleep 1
  VERSION="${VERSION:-0.0.0}" scripts/bundle.sh release | tail -1
  # Sign the dev build with the release identity when the keychain has it.
  # An ad-hoc signature's identity is the build's own hash, so macOS treats
  # every rebuild as a new app and asks for Desktop, Documents, Downloads
  # and the rest again; the Developer ID requirement is the same one the
  # released app carries, so the grants persist between builds.
  if scripts/sign.sh > /dev/null 2>&1; then
    echo "signed as team $(source scripts/lib.sh; echo "$TEAM_ID")"
  else
    echo "unsigned (ad hoc): no Developer ID identity, folder prompts repeat per build"
  fi
  open dist/JitPass.app
  sleep 2
  pgrep -x JitPass > /dev/null && echo "relaunched"
fi
