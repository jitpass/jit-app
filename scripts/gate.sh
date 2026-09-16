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
swift build -c release 2>&1 | grep -E 'error:|Build complete' | { ! grep -q 'error:'; }
swift test 2>&1 | grep -E 'error:|Executed [0-9]+ tests' | tail -1 | grep -q 'with 0 failures'
echo "gate: green"

if [ "${1:-}" = "--run" ]; then
  pkill -x JitPass 2> /dev/null || true
  sleep 1
  VERSION="${VERSION:-0.0.0}" scripts/bundle.sh release | tail -1
  open dist/JitPass.app
  sleep 2
  pgrep -x JitPass > /dev/null && echo "relaunched"
fi
