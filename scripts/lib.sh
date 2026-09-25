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
# The helper's CODE identifier stays "jit", not $HELPER_ID. Every vault's key
# today is a login-keychain item whose ACL trusts the program that made it:
# `identifier jit` + a Developer ID certificate + this team. Signed as
# com.jitpass.agent, the helper was refused that item (errSecAuthFailed), which
# on a real Mac is the "wants to use your confidential information" dialog for
# every existing user. Signed as jit it reads it, and the Secure Enclave
# entitlement still works: the profile authorizes the entitlement, not the
# identifier (jit spike/secure-enclave-mek/FINDINGS.md, S3f).
HELPER_CODE_ID="jit"
# The keychain access group every JitPass Secure Enclave key lives in. Named
# for the vault, not a bundle ID, so moving the helper never orphans a key.
HELPER_GROUP="$TEAM_ID.com.jitpass.vault"
# Where sign.sh finds the helper's Developer ID provisioning profile: CI
# decodes the MACOS_AGENT_PROFILE secret here; a Mac that signs releases keeps
# it beside its other signing material.
AGENT_PROFILE="${AGENT_PROFILE:-$HOME/.apple-signing/JitPass_Agent_Developer_ID.provisionprofile}"

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

# check_agent_profile PROFILE [SIGNER_SHA1]: refuse a provisioning profile
# that would get the helper killed at launch or expire in the field. It must
# be a Developer ID profile (every Mac) for $TEAM_ID.$HELPER_ID, authorize
# $HELPER_GROUP, have at least 90 days left on the profile AND on the
# certificate inside it (the certificate ends first: 2031 against the
# profile's 2044, checked 2026-09-25), and, given SIGNER_SHA1, name exactly
# the certificate that signs the helper. sign.sh runs it before signing;
# verify.sh runs it again on the published helper.
check_agent_profile() {
  local profile="$1" signer="${2:-}" tmp soon
  [ -f "$profile" ] || die "no provisioning profile at $profile"
  tmp=$(mktemp -d)
  security cms -D -i "$profile" > "$tmp/p.plist" 2>/dev/null || { rm -rf "$tmp"; die "$profile is not a provisioning profile"; }
  local appid team all expires groups
  # PlistBuddy, not plutil, for keys with dots in them: its separator is a
  # colon, so "com.apple.application-identifier" needs no escaping.
  local pb=/usr/libexec/PlistBuddy
  appid=$($pb -c "Print :Entitlements:com.apple.application-identifier" "$tmp/p.plist" 2>/dev/null || true)
  team=$($pb -c "Print :TeamIdentifier:0" "$tmp/p.plist" 2>/dev/null || true)
  all=$($pb -c "Print :ProvisionsAllDevices" "$tmp/p.plist" 2>/dev/null || echo false)
  groups=$($pb -c "Print :Entitlements:keychain-access-groups" "$tmp/p.plist" 2>/dev/null || true)
  expires=$(plutil -extract ExpirationDate raw -o - "$tmp/p.plist" 2>/dev/null || true)
  plutil -extract DeveloperCertificates.0 raw -o - "$tmp/p.plist" 2>/dev/null | base64 --decode > "$tmp/cert.der" 2>/dev/null || true
  local certsha
  certsha=$(shasum -a 1 "$tmp/cert.der" | awk '{print toupper($1)}')
  local certok=1
  openssl x509 -inform der -in "$tmp/cert.der" -noout -checkend 7776000 >/dev/null 2>&1 || certok=0
  rm -rf "$tmp"
  [ "$appid" = "$TEAM_ID.$HELPER_ID" ] || die "profile is for '$appid', want $TEAM_ID.$HELPER_ID"
  [ "$team" = "$TEAM_ID" ] || die "profile is team '$team', want $TEAM_ID"
  [ "$all" = "true" ] || die "profile is not a Developer ID profile (it lists devices): a release would run only on those Macs"
  # PlistBuddy prints the array one entry per line, indented.
  [[ $'\n'"$groups"$'\n' == *[[:space:]]"$TEAM_ID.*"$'\n'* || $'\n'"$groups"$'\n' == *[[:space:]]"$HELPER_GROUP"$'\n'* ]] || die "profile does not authorize the keychain group $HELPER_GROUP"
  soon=$(date -u -v+90d +%Y-%m-%dT%H:%M:%SZ)
  [[ "$expires" > "$soon" ]] || die "profile expires $expires, under 90 days away: make a new one in the Apple Developer portal"
  [ "$certok" = 1 ] || die "the certificate in the profile expires within 90 days: renew it and regenerate the profile"
  if [ -n "$signer" ]; then
    [ "$certsha" = "$signer" ] || die "profile names certificate $certsha, but the helper is signed by $signer: macOS would kill it at launch"
  fi
}
