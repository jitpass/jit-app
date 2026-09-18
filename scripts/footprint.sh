#!/bin/bash
# Copyright 2026 Meni Tasa
# SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0
#
# What JitPass has put on this Mac, as text two runs can be diffed by: the
# acceptance test for Remove JitPass (docs/design/offboarding.md, section 7).
#
#   scripts/footprint.sh > before.txt     # a Mac that never had JitPass
#   ... install, set up, then Settings > Remove JitPass ...
#   scripts/footprint.sh > after.txt
#   diff before.txt after.txt             # empty = back to the start
#
# Files are reported by checksum, never by content: several hold secrets.
# Pass extra files or folders to watch (the projects setup will migrate).
set -uo pipefail

sum() { # a file's checksum, or what it is instead
  if [ -L "$1" ]; then echo "link -> $(readlink "$1")"
  elif [ -p "$1" ]; then echo "fifo"
  elif [ -f "$1" ]; then shasum -a 256 "$1" | cut -d' ' -f1
  elif [ -d "$1" ]; then echo "dir"
  else echo "absent"; fi
}

echo "## jit's own"
for p in ~/.jit "$HOME/Library/Application Support/jitpass" \
  ~/Library/LaunchAgents/com.jitpass.agent.plist \
  ~/.terraform.d/plugins/terraform-credentials-jit ~/.cargo/cargo-credential-jit; do
  echo "$p: $(sum "$p")"
done
echo "keychain key: $(security find-generic-password -s com.jitpass.vault.mek >/dev/null 2>&1 && echo present || echo absent)"
echo "service: $(launchctl print "gui/$(id -u)/com.jitpass.agent" >/dev/null 2>&1 && echo loaded || echo absent)"

echo "## the app's own"
echo "preferences: $(defaults read com.jitpass.app 2>/dev/null | shasum -a 256 | cut -d' ' -f1)"
for p in Caches/com.jitpass.app HTTPStorages/com.jitpass.app "Saved Application State/com.jitpass.app.savedState" \
  Preferences/com.jitpass.app.plist; do
  echo "~/Library/$p: $(sum "$HOME/Library/$p")"
done
for p in /opt/homebrew/bin/jit /usr/local/bin/jit; do echo "$p: $(sum "$p")"; done
echo "login item: $(sfltool dumpbtm 2>/dev/null | grep -c com.jitpass.app || true)"

echo "## files jit rewrites"
for p in ~/.zshrc ~/.zprofile ~/.bashrc ~/.bash_profile ~/.profile ~/.zsh_history \
  ~/.aws/config ~/.aws/credentials ~/.kube/config ~/.gitconfig ~/.git-credentials \
  ~/.docker/config.json ~/.terraformrc ~/.terraform.d/credentials.tfrc.json \
  ~/.cargo/config.toml ~/.cargo/credentials.toml ~/.npmrc ~/.netrc ~/.pypirc ~/.clisso.yaml \
  "$HOME/Library/Application Support/Claude/claude_desktop_config.json" ~/.claude.json; do
  echo "$p: $(sum "$p")"
done

echo "## leftovers anywhere under home"
find ~ -maxdepth 6 \( -name '.jit' -o -name '*.pointers' -o -name '*.before-jitpass-removal' \
  -o -name '*.jit-prev' -o -name '*.jit-swap-*' \) -not -path '*/Library/*' 2>/dev/null | sort

for extra in "$@"; do
  echo "## $extra"
  if [ -d "$extra" ]; then
    find "$extra" -not -path '*/.git/*' \( -type f -o -type p -o -type l \) 2>/dev/null | sort | while read -r f; do
      echo "$f: $(sum "$f")"
    done
  else
    echo "$extra: $(sum "$extra")"
  fi
done
