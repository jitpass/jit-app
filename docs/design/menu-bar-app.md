# JitPass menu bar app

**Status: proposed (2026-09-16). Nothing built.** This document specifies the
app, the engine additions it needs, and the order in which they land so that
every step is reversible until the last one.

## Why

Three problems share one fix.

1. **Reach.** Every jit surface is the terminal. The developers who most need
   a credential broker are not all CLI-first, and a security tool nobody
   installs protects nobody.
2. **Unexplained prompts.** The Touch ID dialog is a bare `LAContext` sheet
   with one line of text. It cannot say who asked, why, what "deny" does, or
   how to stop it asking. Prompt fatigue is the most likely reason an
   installed user uninstalls.
3. **Secure Enclave.** `internal/secureenclave` is deferred because keychain
   persistence of an SE key needs a provisioning-profile entitlement that
   only an `.app` bundle can carry (`spike/secure-enclave/FINDINGS.md`,
   re-confirmed 2026-07-11). A bare Mach-O can never have it.

A menu bar app answers all three: it is a GUI, it is where a prompt can
explain itself, and it is the bundle the agent has to live in.

## What it is not

- **Not a new engine.** The Go binaries stay the product: `jit` and
  `jit-agent` do every read, decision, serve and write. The app is a client of
  the agent socket and nothing else. If the app process is killed, jit is
  unchanged.
- **Not mandatory.** Headless use, CI, build boxes and people who dislike menu
  bar icons keep the CLI-only tarball. No CLI code path may require the app.
- **Not a vault browser.** v1 shows names, states and events. It never
  displays a secret value. `jit vault get` stays in the terminal with its
  fresh Touch ID.
- **Not a TUI and not a local web page.** A TUI reaches only the audience the
  CLI already reaches and needs a framework `TECH_STACK.md` R1 rejected. A
  local web app opens a listening port on the machine whose whole point is a
  smaller surface, the reason `design/minting-broker.md` was narrowed.

## Shape

    JitPass.app/
      Contents/
        MacOS/JitPass              Swift, SwiftUI + AppKit, menu bar only (LSUIElement)
        Helpers/jit                Go, unchanged binary from the jit release
        Helpers/jit-agent          Go, unchanged; launchd points here (phase 2)
        Info.plist
        embedded.provisionprofile  phase 3, Secure Enclave entitlement

- **Language: Swift.** Every API the app needs (menu bar item, notifications,
  `LocalAuthentication`, `CryptoKit.SecureEnclave`, signing, entitlements) is
  one native call. Go GUI toolkits and WebView shells each add a large
  dependency and reach the same APIs through a bridge. Swift the language is
  portable; the frameworks are not, and jit is macOS-only by decision
  (`platform-scope-macos-only`), so that costs nothing.
- **Repository: separate, `jitpass/jit-app`, private at first.** Not a fork.
  It contains only the Swift project and pins a released jit version, which
  it downloads at build time and verifies against `checksums.txt` and the
  Developer ID signature the same way `jit upgrade` does. The Go module never
  imports it; CI here never sees it. Reverting the app is archiving that repo.
- **Identity.** Team `CZC6BH93GJ`, bundle id `com.jitpass.app`, decided once:
  the SE entitlement and keychain access group are keyed on it and changing
  either later orphans keys. The launchd label stays `com.jitpass.agent`.
- **One agent.** The app talks to the same socket path the CLI uses and runs
  the same protocol handshake (`Request.MinProtocol`, `Response` protocol
  number). A Homebrew CLI and the app on one machine share one agent, never
  two.

## What v1 shows

The dropdown, top to bottom. Each row is a socket op the CLI can also send.

| Row | Socket op | CLI equivalent |
|---|---|---|
| Lock glyph in the menu bar: locked / unlocked with countdown | `status` (polled) + `subscribe` | `jit service status` |
| Lock now / Unlock | `lock`, `unlock` | `jit lock`, `jit unlock` |
| Active grants: holder, profiles, expiry, serve count; Revoke | `grant_list`, `grant_revoke` | `jit grant list`, `jit grant revoke` |
| Last N events, live | `subscribe` | `jit audit -f` |
| Pending consent request with Deny / Allow with Touch ID (phase 4) | `subscribe` with `broker`, `consent_list`, `consent_answer` | none; the dialog itself is the CLI's view |
| Open jit audit / doctor in Terminal | none | shell out |

Notifications, opt-in per kind: session locked (with why: idle, ceiling,
screen lock, sleep), grant ended, a **decoy was served** to a reader outside
any grant, a consent request denied N times in a row (the loop signal
`consentReason` already counts).

Nothing in the app decides anything. Revoke is the only mutating action and
it needs no auth today (`jit grant revoke` is unauthenticated by design:
reducing access is free). Unlock triggers the agent's own challenge.

## Engine additions

All additive. Each is a separate PR, useful to the CLI on its own, and stays
if the app is abandoned.

1. **`subscribe` op** (`OpSubscribe`). A long-lived connection on which the
   agent streams `SessionEvent` records as they happen, newline-delimited,
   same shape `history` returns. Peer is verified same-user like every other
   op. `jit audit -f` today re-reads a file; it moves onto this and gets
   sub-second latency for free. Bumps `Protocol` to 2; a client that sends
   `subscribe` to a protocol-1 agent gets the existing unknown-op error.
2. **Richer `status`.** Add `locks_at` (absolute), `lock_reason` of the last
   lock, `ceiling_at`, `consent_enabled`, `protocol`. `jit status` prints the
   new fields; no field is removed.
3. **Consent brokering ops** (phase 4, shipped): a subscriber that sets
   `broker` on `subscribe` is streamed a `pending` event for every disclosed
   challenge (consent gate, grant create/extend, trust, `--with`) before its
   Touch ID appears; `consent_list` returns the ones waiting; `consent_answer`
   carries `allow` or `deny`. The hook is in the one function every disclosed
   challenge already passes through (`discloseChallengeOp`), not in
   `consent.Prompter`, so `internal/consent` stays pure and every prompt kind
   is covered by one implementation. `allow` proceeds to the agent's own
   Touch ID; `deny` refuses with no dialog; no answer within ninety seconds
   is a refusal; a broker that disconnects mid-request falls back to the
   dialog. The outcome event carries the request's `consent_id`. This is the
   only addition that touches a decision path, and it never adds authority:
   the app can only refuse or ask the human.

Nothing else in `internal/agent` changes. `internal/consent` stays pure.

## Phases and how each reverts

| Phase | Lands where | Revert |
|---|---|---|
| 0. This doc + `subscribe` + richer `status` | `jitpass/jit` | Leave them; CLI-useful |
| 1. App v0.1: read-only dropdown, lock/unlock, grants, live events. Temporary cask `jit-app` in the tap, depends on the `jitpass` cask | `jitpass/jit-app`, tap | Deprecate the cask; `jitpass` cask untouched |
| 2. (shipped) `jit` (one binary: CLI and service) inside the bundle at `Contents/MacOS/jit`, fetched from the pinned release in `jit.version` and verified like `jit upgrade` verifies. `jitpass` cask, owned by the app release, installs the app and symlinks that jit via `binary`; version `<jit>,<app>`. The launchd plist records the symlink target inside /Applications, which survives `brew upgrade`. `jit upgrade` refuses inside a bundle and points at the app. `jit-app` cask deprecated with `replacement_cask`. Tarball stays CLI-only | `jitpass/jit-app` release, tap, jit `upgrade.go` | One tap PR pointing the cask back at the tarball; jit's goreleaser cask block restored from history |
| 3. Secure Enclave wrapper, opt-in: `jit vault rekey --wrapper secure-enclave`, and the reverse `--wrapper keychain`. `keychainwrap` remains the default for new vaults | `jitpass/jit` | Users run the reverse rekey; default never moved |
| 4. Consent prompts brokered through the app when it is running | both | Delete the Prompter implementation; `LAContext` path is the fallback and never left |

Phase 2 is the first change to the shipped install path; it is one reviewed
PR. Phase 3's opt-in must ship with the reverse rekey tested end to end
before the flag is visible. Making Secure Enclave the default for new vaults
is a separate, later decision and the only one-way door in this plan.

## Direct download (shipped)

Homebrew is the recommended install and the only one that keeps itself
current, but a security tool that can only be had through a package manager
loses the people who came from the website. The release therefore also
publishes the zip under an unversioned name, `JitPass-arm64.zip`, so one
link never goes stale:

    https://dl.jitpass.com/jitpass/jit-app/releases/latest/download/JitPass-arm64.zip

The same bytes as the versioned zip, listed in `checksums.txt` and checked
in the release workflow against the copy just verified; the cask keeps the
versioned name, pinned by sha256. `dl.jitpass.com` is the one-hop redirect
the cask already uses (`spike/dl-redirect` in the jit repo), so GitHub stays
the only origin serving bytes and the download is counted by client class
and country, nothing more.

What the cask did for a Homebrew install, the app does for itself:

- **PATH.** On first launch, when no `jit` is on the login shell's PATH and
  no Caskroom says Homebrew owns the link, the app offers once to link
  `jit` at the bundled copy: Homebrew's bin when it exists and is writable,
  else `/usr/local/bin` through the system's administrator prompt. Settings
  › General keeps the same button and shows which `jit` a terminal runs, so
  an older tarball install sitting earlier on PATH is named rather than
  silently shadowing the app's.
- **Updates.** Once a day the app sends one HEAD request to GitHub's
  `releases/latest` and reads the version from the redirect it answers
  with: no API token, no rate limit, nothing about the Mac in the request.
  It is the only network request the app makes and Settings can switch it
  off. A newer version is an amber Update row in the panel; a Homebrew
  install is sent to `brew upgrade jitpass`, a downloaded copy to the link
  above. The app never replaces itself: that is Sparkle-sized machinery
  and a second signed code path, for a zip that is a drag to replace.
- **Translocation.** A copy opened from ~/Downloads runs from a randomized
  read-only path, and every link and launchd plist made from there dies
  with it. The app says so before anything is set up and asks to be moved.

`jit upgrade` inside the bundle keeps refusing and pointing at the app.

## Confirmation dialogs

The app passes `--yes` to every jit command it runs, which answers jit's own
[y/N] before it is asked. Its dialog is therefore the only question the user
is ever asked, and it is worded for the person, not for whoever wrote jit:

- **Lead with what changes**, and with the irreversible part of it first
  ("It deletes all 3 secrets and their history for good, with no archive and
  no undo"). End with what happens next, which is usually "Touch ID follows."
- **Never quote the command.** `This runs: jit vault orphans --prune --yes`
  answers a question about jit's flags; the reader is deciding about their
  secrets. Two exceptions, both cases where the command IS the decision: a
  `--break-profiles` delete, where that flag is what makes jit delete what it
  would otherwise refuse, and anything the app hands to the terminal, where
  the command is literally what the user is about to be given.
- **Whatever the command carried, the sentence must carry.** A quoted command
  is often the only place a path, a file or a list of names appears. Removing
  it without moving those names into the prose loses a fact
  (`DoctorAdvice.subject(of:)`, `StatusItemController.protectedNames`). When
  a command names several things, name all of them: a sentence that says one
  path while the command deletes two understates a delete.
- **"Nothing asks again" is not a fact about the user's decision.** It
  describes the `--yes` above, it is true of every one of these dialogs, and
  it distinguishes nothing.
- A dialog that only informs takes no destructive button; one that deletes
  takes the red one (`hasDestructiveAction`), and a delete that breaks a
  profile takes no Return key at all.

## Security notes

- The app adds no new privileged path. It is a same-user socket peer, subject
  to the same peercred check as any jit process, and cannot do anything the
  CLI cannot.
- The app never receives a DEK or a plaintext. `wrap`/`unwrap` are not in its
  vocabulary and the agent could refuse them from a peer whose exec path is
  the app bundle, but that would be a process-name gate, which jit does not
  build; the real boundary is that the app never asks.
- `subscribe` streams the same records `history` already returns to any
  same-user peer; no new information is exposed.
- Bundling the agent moves its code-signing identity from a bare Mach-O to
  the app's signature. `verifyStagedSignature` and `upgradeTeamIDs` apply to
  the bundle exactly as they do to the binary today; a bundle cannot be
  stapled either, so the online notarization ticket story is unchanged.
- The CGo surface does not grow: Secure Enclave lands in
  `internal/secureenclave`, already one of the named packages, behind the
  existing `vault.KeyWrapper` interface.

## Open questions

- Does the app poll `status` or rely solely on `subscribe` plus a lock-state
  event? Proposed: subscribe, with a 30s poll as a liveness check.
- Sandbox: an App Sandbox entitlement would block the Unix socket in
  `~/Library/Application Support`. Proposed: not sandboxed, hardened runtime
  only, same as the CLI today.
- Whether the app should launch at login by default. Proposed: yes when
  installed via the app cask, since the agent already does, and one toggle in
  the dropdown turns it off.
