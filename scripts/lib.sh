#!/bin/zsh
# Copyright 2026 Meni Tasa
# SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0
#
# Shared constants for the release scripts. Sourced, never run.
# shellcheck disable=SC2034  # every name here is used by the scripts that source it

# The Apple Team ID every release must be signed under. The same value jit's
# upgradeTeamIDs[0] names: a bundle signed by any other team is not a
# release, however valid its signature.
TEAM_ID="CZC6BH93GJ"

APP_NAME="JitPass"
BUNDLE_ID="com.jitpass.app"
DIST="dist"
APP="$DIST/$APP_NAME.app"

# jit's own bundle inside the app (Secure Enclave plan, step A1). A
# provisioning profile authorizes only a bundle's MAIN executable, so the
# Secure Enclave entitlement (step A2) needs jit to be one; a second
# executable in JitPass.app is killed at launch (jit's
# spike/secure-enclave-mek/FINDINGS.md, S3a). The old path,
# Contents/MacOS/jit, stays as a symlink into it: every installed launchd
# plist and every PATH link names that path (S3e).
HELPER_NAME="JitPassAgent"
HELPER_ID="com.jitpass.agent"
HELPER="$APP/Contents/Helpers/$HELPER_NAME.app"
HELPER_JIT_REL="Contents/Helpers/$HELPER_NAME.app/Contents/MacOS/jit"

# The jit release bundled into the app, pinned in jit.version at the repo
# root. The app is a client of that exact CLI and service, so the pin is
# reviewed like any other dependency; bump it on purpose, in its own commit.
JIT_VERSION_FILE="jit.version"
JIT_REPO="jitpass/jit"

jit_version() {
  tr -d '[:space:]' < "$JIT_VERSION_FILE"
}

# Where fetch-jit.sh leaves the verified binary and completions for bundle.sh.
jit_stage() {
  echo "$DIST/jit-$(jit_version)"
}

# Versions come from the tag (v0.1.0 -> 0.1.0); a local build with no tag
# stamps 0.0.0 so an unversioned bundle can never be mistaken for a release.
version_from_env() {
  local v="${VERSION:-${GITHUB_REF_NAME:-}}"
  v="${v#v}"
  echo "${v:-0.0.0}"
}

artifact_name() {
  echo "$APP_NAME-$(version_from_env)-arm64.zip"
}

# The unversioned copy of the same zip, for the stable /releases/latest link.
latest_artifact_name() {
  echo "$APP_NAME-arm64.zip"
}

die() {
  echo "error: $*" >&2
  exit 1
}
