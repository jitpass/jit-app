# Onboarding: a new user, no terminal

Status: plan, 2026-09-18. Nothing here is built. Section 2 is what the code
does today; everything marked **verify** is an assumption to test in phase 0
before any of it is relied on.

Mockups (first pass, 2026-09-18): https://claude.ai/artifact/CmYsJk8hpfjm8uaqu1iu9d,
sources in `docs/design/mockups/onboarding/`.

## 1. The goal

Someone downloads JitPass from the website, opens it, and within two
minutes has their plaintext secrets in a Touch ID vault with every tool
still working. They never open a terminal, never read a doc, and never see
a state that looks broken.

The CLI already has this arc for a terminal user: bare `jit` on a fresh Mac
runs `firstRun` (`internal/cli/firstrun.go`): read-only scan, "here's what's
exposed", one y/N, then `jit vault init` and `jit migrate`. The app reuses
the same order and the same commands. It invents no new engine behaviour.

## 2. What a fresh Mac gets today

Read from the code on 2026-09-18 (app `e512ab6`, jit `65470df`).

| # | What happens | Where | Why it hurts |
|---|---|---|---|
| 1 | Double-clicking the app shows nothing but a small red ring in the menu bar | `main.swift` sets `.accessory`; no window opens on launch | "Did it open?" The first impression is an error colour |
| 2 | The panel says "Not running · the service is not running" | `SessionState.notRunning`, `StatusMark` maps it to red | A fresh install reads as a fault |
| 3 | **"Start Service" does nothing** | `unlockNow()` sends the `unlock` op to a socket that does not exist; the error is dropped by `try?` | A real bug. Only `jit service unlock` installs the service (`ensureAgentInstalled`, `servicecmds.go:339`), and the app never spawns it |
| 4 | **Protect fails on a fresh Mac** | `protectPlan` runs `jit migrate … --yes`; nothing ran `jit vault init`, so `fetchMEK` asks for Touch ID and then fails on a missing keychain item | The user gives a fingerprint and gets a raw keychain error |
| 5 | The app cannot tell "no vault yet" from "vault with 0 secrets" | `jit status --format json` has no such field; doctor's `vault_key` finding only fires when the vault already holds secrets | There is nothing to hang a setup state on |
| 6 | A whole-Mac scan raises one macOS prompt per protected folder unless Full Disk Access is granted; the background scan does not run at all without it | `refreshScanIfDue`, `ScanReportView.chooser` | The "Protected" row stays empty, and the first scan is a wall of permission dialogs |
| 7 | Up to three unrelated dialogs stack on first launch | Translocation warning (`AppDelegate`), "Install the jit command line tool?" two seconds in (`offerCommandLineToolOnce`), and the notification permission when either switch is on | Each asks for something before the user knows what the app is |
| 8 | Launch at login is off and lives only in Settings | `SMAppService` in `StatusItemController+Settings` | After a reboot the app is gone and the user forgets it exists |
| 9 | Nothing ever suggests a backup until doctor complains | `export_recorded` in status | The vault decrypts only on this Mac; losing it loses everything |

The building blocks all exist and are in-app already: the ndjson scan and
`ProtectPlan`, `JitCLI.execute` with `--yes`/`--stdin`, the consent
auto-allow for app-spawned jit (`JitCLI.spawned`), the tool listing with
`--discover`, the guard toggle, the export sheet with a passphrase on
stdin, the PATH link installer. Onboarding is sequencing, not new machinery.

## 3. Principles

1. **Value before any ask.** The first thing the user sees is their own
   exposure number, not a permission request, an account form or a tour.
2. **One decision per screen, one primary button.** Return presses it.
3. **Every system prompt is announced before it appears.** "Touch ID
   follows." "macOS will ask to allow notifications." No prompt without a
   click behind it (the rule `refreshScanIfDue` already states).
4. **Never a dead end.** Every screen after the scan can be skipped, the
   window can be closed at any point, and the panel offers "Continue Setup".
5. **State comes from the engine, not from a flag.** Which step to show is
   derived from what is true (vault exists? secrets stored? FDA?), so a CLI
   user who installs the app never sees onboarding, and a half-finished
   setup resumes at the right step after a crash or reboot.
6. **Same commands as the CLI.** Each step names the command it runs in a
   disclosure ("What this runs"), as the Protect dialog does today.
7. **No fake progress.** The progress screen ticks real steps as each
   spawned command returns.

## 4. The flow

One fixed-size window (about 620 × 520, not resizable, centred, the panel's
material and the ring-and-dot mark). It opens by itself on first launch and
activates the app, because an accessory app otherwise shows nothing. Five
screens, no step counter longer than five dots.

### Screen 1: Welcome

> **Your secrets are sitting in plain files.**
> API keys in `.env`, tokens in `.npmrc`, cloud credentials in `~/.aws`.
> Anything running as you can read them. JitPass moves them into a vault
> that opens with your fingerprint, and your tools keep working.
>
> First, a look. It only reads, and nothing leaves this Mac.
>
> | **Quick scan** | **Full scan** |
> |---|---|
> | About 5 seconds, no permissions | Every folder, the complete number |
> | Skips Desktop, Documents and Downloads | Needs Full Disk Access: one switch in System Settings |
> | [ **Quick Scan** ] | [ **Full Scan…** ] |
>
> or choose a folder…

The user decides how deep the first look goes (decided 2026-09-18); the app
does not pick for them. Each card says what it costs and what it misses, in
two lines, so the choice is informed and not a guess. Return presses Quick
Scan only because it is the one that needs nothing; neither card is dimmed
or labelled "recommended".

- **Full Scan…** with Full Disk Access already granted starts at once. Without
  it, the card turns into the grant step in place: why, a button that opens
  the right System Settings pane, live detection (poll
  `FullDiskAccess.granted()` each second), and the scan starts by itself
  when the switch flips. "Use Quick Scan instead" is always there, so the
  System Settings trip is never a trap.
- **choose a folder…** is the Scan window's existing picker, for someone who
  wants to try one project first.

No "Skip" here: closing the window is the skip.

### Screen 2: What we found

The scan starts on the button press and the screen shows a live count as
ndjson lines arrive (files walked, findings so far), so five seconds feel
like work and not like a hang.

**A quick scan cannot raise a macOS prompt.** It
passes `--exclude` for the TCC-protected folders (`~/Desktop`,
`~/Documents`, `~/Downloads`, iCloud Drive, the protected parts of
`~/Library`). Excludes prune the walk (`walkHomeDirExcluding`), so those
folders are never opened. Dotfiles, `~/.aws`, `~/.config`, shell rc files
and any `~/code`-style project folder are all outside TCC, and that is
where most findings live. **verify**: the exact folder list on macOS 26,
and that a pruned folder raises no prompt.

Result:

> **23 secrets in plain text**
> 0% protected
>
> ● JitPass can protect **18** right now · 9 files, 3 tools
> ○ 5 need you (rotate or remove) — we'll show you how after
>
> `~/.aws/credentials`  aws_secret_access_key  `wJal…EKEY`
> `~/code/shop/.env`  STRIPE_SECRET_KEY  `sk_l…9f2a`
> … 7 more files
>
> ▸ Desktop, Documents and Downloads were not scanned. [Include them…]
>
> [ **Protect 18 Secrets** ]   Not now

- Values are the scan's own masked previews; the app never holds a value.
- The "were not scanned" line shows only after a quick or folder scan, and
  names exactly what was left out. "Include them…" is the same grant step
  as Welcome's Full Scan card, so someone who chose quick can still go
  deeper without starting over. **verify**: whether macOS
  demands "Quit & Reopen" for the grant to reach the spawned `jit`; if it
  does, onboarding must resume on this screen after relaunch (principle 5
  already gives that).
- "What will change" disclosure lists each file and tool, from the same
  `ProtectPlan` the Scan window builds.
- "Not now" goes to a one-line screen: "Nothing was changed. Setup is in
  the menu bar whenever you want it", and the panel shows Continue Setup.
- **Zero findings**: "Nothing exposed in the places we looked." The primary
  button becomes "Create My Vault", and the last screen offers "Add your
  first secret" (the Vault window's existing add sheet).

### Screen 3: Protecting

The button is the consent (it named the count and the files), so there is
no second "are you sure" alert. A checklist ticks live:

> ✓ Vault created — key stored in your login keychain
> ◌ Waiting for Touch ID…
> · Moving 18 secrets, rewriting 9 files (each backed up first)
> · Protecting gh, aws, npm
> · Checking the result

Runs, in order, through `JitCLI.execute`: `vault init`, then
`migrate <files> --yes` (which installs and starts the service by itself),
then `wrap <tool>` per tool, then a rescan. One Touch ID in the normal
case; the consent sheet stays out of the way because these are
app-spawned pids.

Failure is per row: a cancelled Touch ID turns the row amber with "Try
Again"; a failed command shows its last line and "Show Details" (the full
output, as `showResult` does now). Rows already done stay done, because
each command is idempotent and the next attempt re-derives the plan from a
fresh scan.

### Screen 4: Finish setting up

The payoff first, then a short list of switches. Nothing here blocks Done.

> **78% protected.** 18 secrets are in the vault. Your tools work as before;
> macOS asks for Touch ID about once per 5 minutes of use.
> Changed your mind? Every file can be restored. [Undo…]

| Row | Default | Runs |
|---|---|---|
| **Save a recovery file** — "Your vault opens only on this Mac. A recovery file and a passphrase bring it back on a new one." | button, visually first | the existing export sheet (`vault export --stdin`) |
| Open JitPass at login | on | `SMAppService.mainApp.register()` |
| Tell me when something reads a protected file without permission | on, macOS asks once | `Notifier.requestPermission()` |
| Keep secrets out of shell history | off: it edits the user's `~/.zshrc`, so it is theirs to switch on | `guard history` |
| Use `jit` in Terminal | shown only off Homebrew and when `jit` is not on PATH | the existing `installCommandLineTool()` |

Switches apply on "Done", so one click confirms all of them and the
notification prompt appears at a moment the user expects it.

### Screen 5: It lives up here

The window closes, and the panel opens by itself under the status item,
now green, with a one-time callout: "JitPass lives here. Click the ring
any time." The five secrets that need the user appear as the Protected
row's amber dot, which opens the Scan window as it does today. That is the
hand-off from onboarding to the normal product.

## 5. The panel before setup

A third presentation next to locked and not-running: **Set up JitPass**.
The header reads "Not set up yet · takes about two minutes", the only
primary action is "Continue Setup…", and the rows that have nothing to
show (Grants, Vault, Tools, AI Agents, Doctor) are hidden, leaving
Settings, About and Quit. The menu bar mark must not be red here. Proposal:
a hollow amber ring, the GUI twin of the CLI's `○` "not yet". This is a
mockup decision.

## 6. Changes

### Engine (`jitpass/jit`, additive, ships first)

- **E1** `jit status --format json` gains `vault.initialized`:
  `"yes" | "no" | "unknown"`, from `keychainwrap.MEKPresence()`, which is
  already prompt-free. `unknown` must never trigger onboarding.
- **E2** A missing master key becomes a plain sentence wherever a command
  needs it (`migrate`, `wrap`, `vault set`): "no vault on this Mac yet, run
  `jit vault init`", checked with `MEKPresence` **before** the Touch ID
  challenge. Today the user authenticates and then gets a keychain error.
  This fixes the CLI too.
- No new socket ops. The `AgentOp` rule is untouched.

### App (`jitpass/jit-app`)

| Piece | File |
|---|---|
| Decode `vault.initialized` | `JitAgentClient/CLIStatus.swift` |
| Pure step machine: (initialized, secrets stored, scan, FDA, dismissed) → step. No AppKit, fully unit-tested | new `JitAgentClient/Onboarding.swift` + tests |
| Window: fixed size, centred, activates the app | new `OnboardingWindow.swift` |
| Five screens | new `OnboardingView.swift` (+ one file per screen if it passes ~300 lines) |
| Orchestration, reusing `JitCLI.scan`, `ProtectPlan`, `JitCLI.execute` | new `StatusItemController+Onboarding.swift` |
| Live scan count needs streaming ndjson instead of read-to-end | `JitCLI.scan` gains a line callback |
| "Set up" presentation | `PanelView`, `MenuModel`, `StatusMark` |
| **Fix** Start Service: when not running, spawn `jit service unlock` | `StatusItemController.unlockNow` |
| **Fix** Protect with no vault routes into setup instead of failing | `StatusItemController+Scan.protectPlan` |
| Hold the PATH offer and the notification request while onboarding owns the first launch | `StatusItemController.start`, `+Updates`, `+Notifications` |
| "Run Setup Again" | Settings › General |
| Restore screen (recovery file + passphrase), reusing the import sheet's plumbing | `OnboardingView`, `StatusItemController+VaultMaintenance` |
| Reopen brings setup (or the panel) forward; quitting mid-protect asks first | `AppDelegate` |
| Translocation becomes a setup screen for a Mac with no vault | `Translocation.swift`, `AppDelegate` |

## 7. Phases

0. **Verify and draw.** Test the **verify** items on a brand-new macOS user
   account on this Mac: a second account has its own keychain, home and TCC
   grants, so it is an honest fresh machine and costs nothing. Mock the five
   screens and the set-up panel in `docs/design/mockups/`, light and dark,
   and agree them by eye before any Swift.
1. **Engine**: E1 and E2, one jit release, bump `jit.version`.
2. **Foundations, shippable alone**: state detection, the set-up panel, the
   Start Service fix, the Protect guard. After this no fresh user sees a
   broken state, even with no onboarding window yet.
3. **The window**: Welcome, quick scan, results, protecting.
4. **Finish screen**: recovery file, login item, notifications, guard,
   PATH; absorb the first-launch dialogs; the panel hand-off.
5. **Edges**: everything in section 8 that phases 2 to 4 did not already
   need. The "who must not get the flow" table is not phase 5 work: it is
   the step machine's unit tests, written in phase 2.

Each phase ends on the fresh account from phase 0, start to finish, with no
terminal open.

## 8. Edge cases

The rule behind all of them: the step shown is derived from engine state
(principle 5), every spawned command is idempotent, and a failure is a row
with a sentence and a retry, never a dead window.

### Who must not get the new-user flow

| Case | How it is seen | What happens |
|---|---|---|
| Existing CLI user installs the app | `initialized = yes` | No onboarding at all, ever. The panel is today's |
| Ran `jit vault init` only, or setup stopped after the vault was made | `yes`, 0 secrets | No auto-opening window. The panel offers "Continue Setup", which opens on the results screen, not Welcome |
| **Vault files present, key missing** (home restored from a file backup, a new Mac without the keychain) | `no`, but `secrets_stored > 0` | This is doctor's total-loss state, not a new user. Onboarding must not quietly run `vault init` over it. It opens a Restore screen: "This Mac has a vault it cannot open" → recovery file + passphrase (`vault init`, then `vault import --stdin --yes`) |
| **Moving to a new Mac** | fresh Mac, user holds a recovery file | Welcome carries one quiet link under the button: "Moving from another Mac? Restore from a recovery file." Same Restore screen |
| Keychain not answerable (locked at login, MDM keychain, an error) | `unknown` | Never onboarding, never the set-up mark. Today's panel, and the next status read decides |
| Bundled jit predates E1 (a dev build falling back to a Homebrew jit) | field absent | Treated as `unknown` |
| The user wants the terminal only | set-up panel has "I'll set up in Terminal" | A flag hides the set-up presentation. The only place a flag outranks state, because only the user can know this |
| Vault deleted later (`jit vault delete`) | `no` again | The set-up panel returns; the window does not auto-open a second time |
| App removed and reinstalled | key and vault persist | No onboarding. Correct |

### Launch

- **Translocated copy.** A service plist must never record a temporary
  path. While translocated, the window shows only "Move JitPass to
  Applications" and setup cannot start; "Continue Anyway" goes away for a
  Mac with no vault. This replaces the launch alert for new users.
- **The user opens the app again because nothing seemed to happen.** The
  app has no `applicationShouldHandleReopen` today. Add it: reopening
  brings the onboarding window forward, or opens the panel once set up.
- **The status item is hidden.** On a notched MacBook with a full menu bar
  macOS silently drops items that do not fit, and the last screen's "it
  lives up here" would point at nothing. Check the status button's window
  is on screen; when it is not, say so ("Your menu bar is full. JitPass is
  hidden behind the notch") and rely on reopen as the way in. **verify**
  how reliably occlusion can be detected.
- **Damaged bundle** (`JitCLI.executable == nil`): one screen, "This copy of
  JitPass is incomplete. Download it again", not an empty scan.
- **Second display, full-screen Space**: centre on the screen with the
  pointer; the window joins the active Space.
- **An update arrives mid-setup**: the Update row and its alert wait until
  setup is finished or dismissed.

### Scan

- **Slow scan** (a huge home, deep `node_modules`): the live count keeps
  moving, and a Cancel button terminates the process and returns to
  Welcome. No timeout that kills a legitimately long scan.
- **Scan fails or prints no summary**: the error's last line, "Try Again",
  and "Create my vault anyway" so a scanner bug never blocks setup.
- **Hundreds of findings**: five rows by severity and "… 212 more"; the
  full list stays in the Scan window.
- **Findings, none of them migratable**: the button is "Create My Vault"
  and the screen explains what needs the user, not a promise of 0.
- **The Mac changes between scan and Protect**: migrate re-plans by itself,
  so the result screen reports the rescan's numbers, never the promised
  ones. "18" on the button can honestly become "17 protected, 1 changed
  while we worked".
- **Secrets in a git repository.** Migrating rewrites a tracked file and
  does not scrub history; the CLI already says so (`migratesummary.go`).
  The result screen repeats it in one line per repo: "still in git history
  — rotate this key", and those count under "need you".
- **Shell rc files rewritten**: terminals already open keep the old
  environment. One line on the result screen: "Open a new terminal window."
- **Symlinked dotfiles** (stow, chezmoi in symlink mode). Checked in code:
  the scan never reports a symlink and migrate never rewrites through one
  (`internal/migrate/apply.go:208`), so these files are neither found nor
  touched. Nothing can go wrong in setup, but the number is incomplete for
  such a user and nothing says so. An engine gap to note, not onboarding
  work.

### Protect

- **No Touch ID** (Mac mini or Studio without a Touch ID keyboard, lid
  closed on an external display): macOS asks for the password instead. Ask
  `LAContext` which is available and word every prompt announcement to
  match ("your fingerprint" / "your Mac password").
- **Touch ID cancelled, failed or timed out**: the row turns amber with
  "Try Again". The vault stays created, no file has been touched yet.
- **Partial failure** (a read-only file, a root-owned file, a full disk):
  that row is red with the command's last line; finished rows stay
  finished; the rescan tells the truth; Undo is offered.
- **One tool's wrap fails** (key not found, the tool needs a login first):
  the others continue, and that tool moves to "need you" with its reason.
- **1Password is installed.** Checked in code: when `op` is on PATH,
  migrate consults it by default (`migrate.go:779`, `migrateOpInstalled`)
  and vaults a matching value as an `op://` reference, so 1Password asks
  for its own authorisation in the middle of setup. The user decides here
  too: when `JitCLI.onePasswordCLIInstalled`, the results screen shows one
  switch, "Link values that already live in 1Password · 1Password will ask
  to authorise", on as the engine's default is; off passes
  `--no-1password`. **verify** on the fresh account what the prompt looks
  like from a spawned process, and that a denied prompt fails the row
  cleanly and not the whole migrate.
- **macOS announces a background item.** Installing the LaunchAgent raises
  the system's "Background Items Added" notification, under the signing
  name. The protecting screen says it is coming. If the user has switched
  it off in System Settings › Login Items, the service never answers:
  detect `installed && !running` after the wait and show how to turn it
  back on, not a generic failure.
- **Managed Mac** (MDM blocks Full Disk Access or LaunchAgents): the quick
  scan still works, FDA stays an optional card, and a blocked service gets
  the same sentence as above with "ask your administrator".
- **Quit, crash, sleep or screen lock mid-protect**: the window cannot be
  closed during this step, and `applicationShouldTerminate` asks first
  ("Setup is moving secrets. Quit anyway?"). If it dies regardless, a
  spawned jit finishes or fails by itself, every file it touched has an
  encrypted backup, and the next launch derives the step from what is true.
- **The user runs `jit vault init` in a terminal while the window is
  open**: the status read flips and the window moves on; `vault init` is
  idempotent either way.

### Finish screen

- **Recovery file**: passphrase typed twice, empty or mismatched refused
  inline, and one plain sentence that a lost passphrase cannot be
  recovered by anyone. Suggest a place that is not only this Mac.
- **Login item fails** (not in /Applications, a dev build): the error sits
  inline on its row and Done still works.
- **Notifications denied earlier or by policy**: the switch shows "Off in
  System Settings" with a link, and no request is sent that macOS would
  ignore.
- **The login shell is not zsh**: the history guard row is hidden (the hook
  is zsh only), not shown disabled with an apology.
- **PATH link needs an administrator and the user cancels**: the row stays
  off, nothing else changes.

### Coming back

- The window auto-opens **once**. After that setup is reachable only from
  the panel and Settings; no reminder notifications, no reopening on every
  launch.
- Closing mid-way never loses work: the quick scan's result is kept in
  memory for the session and redone on the next, since a stale exposure
  number is worse than a five-second wait.

### Every screen

VoiceOver labels and a sensible focus order, Return for the primary button
and Esc to close, Reduce Motion (no ticking animation), Reduce Transparency
and Increase Contrast (a solid background instead of the material), light
and dark, larger text without clipping. English only, but no fixed-width
labels.

## 9. Decisions (2026-09-18)

1. **The user chooses the first scan's depth**: Quick Scan, Full Scan or a
   folder, side by side on Welcome. The app does not decide for them.
2. **"Not set up" is a hollow amber ring**, the GUI twin of the CLI's `○`.
3. **Open at login defaults to on** in the finish screen, confirmed by
   Done. The history guard defaults to off, because it edits `~/.zshrc`.
