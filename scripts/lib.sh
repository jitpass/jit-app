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

die() {
  echo "error: $*" >&2
  exit 1
}
