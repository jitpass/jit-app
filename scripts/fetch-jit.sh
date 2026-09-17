#!/bin/zsh
# Copyright 2026 Meni Tasa
# SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0
#
# Fetch the jit release pinned in jit.version and verify it the way
# `jit upgrade` would before it installs anything: the tarball against the
# release's own checksums.txt, then the binary's Developer ID signature and
# team, then the version it reports. Nothing unverified reaches the bundle.
# Downloads straight from github.com, the only origin that serves the bytes;
# the dl.jitpass.com redirect is for user installs, never for the release
# pipeline. Cached under dist/ per version, so a rebuild fetches nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

version="$(jit_version)"
stage="$(jit_stage)"
if [ -x "$stage/jit" ] && [ -f "$stage/completions/_jit" ]; then
  echo "jit $version already fetched into $stage"
  exit 0
fi

base="https://github.com/$JIT_REPO/releases/download/v$version"
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/jitpass_darwin_arm64.tar.gz" "$base/jitpass_darwin_arm64.tar.gz"
curl -fsSL -o "$tmp/checksums.txt" "$base/checksums.txt"
actual=$(shasum -a 256 "$tmp/jitpass_darwin_arm64.tar.gz" | cut -d' ' -f1)
claimed=$(grep 'jitpass_darwin_arm64.tar.gz' "$tmp/checksums.txt" | cut -d' ' -f1)
[ "$actual" = "$claimed" ] || die "jit $version tarball sha256 $actual does not match checksums.txt ($claimed)"

rm -rf "$stage"
mkdir -p "$stage"
tar -xzf "$tmp/jitpass_darwin_arm64.tar.gz" -C "$stage" jit completions
rm -rf "$tmp"

codesign --verify --strict "$stage/jit"
info=$(codesign --display --verbose=2 "$stage/jit" 2>&1)
[[ "$info" == *"TeamIdentifier=$TEAM_ID"* ]] || die "jit $version is not signed by team $TEAM_ID"
[[ "$info" == *"(runtime)"* ]] || die "jit $version lacks the hardened runtime; the bundle could not be notarized"
got=$("$stage/jit" --version)
[[ "$got" == *"$version"* ]] || die "downloaded jit reports '$got', want $version"
echo "fetched and verified jit $version into $stage"
