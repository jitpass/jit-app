# Offboarding: remove JitPass, back to the start

Status, 2026-09-18: built. Engine: jit PRs #127 (6.1) and #128 (6.2, 6.3).
App: branch `offboarding`. Nothing is released; the app needs a jit release
that carries #128 before `jit.version` can move, and until then the window
says this copy of jit is too old. No real removal has been run on a real
machine yet: phase 0 and the acceptance loop (section 7) are still to do on
the VM. Where the build differs from the plan below, the difference is
marked **as built**. Decisions in section 9 are made.

Section 2 was read from the code and then audited a second time against it (app `8a90b0d`, jit `3e56d3d`, both 1.7.0); file and line
references are in section 10. Everything marked **verify** is an assumption
to test on the VM before it is relied on.

Mockups: https://claude.ai/artifact/Hu6pKgXWDvgAXw5wWzFYJ3, sources in
`docs/design/mockups/offboarding/`.

## 1. The goal

One button in Settings that leaves the Mac as it was before JitPass: every
file jit rewrote holds its secrets as plaintext again, nothing of jit's runs,
and nothing of jit's is left on disk, in the keychain or in a shell config.

The test of "the start" is concrete: **install the app again and it opens
onboarding at Welcome**, with the hollow amber ring, as on a Mac that never
had it. Two people need this: someone leaving, and us, re-running onboarding
on a VM without rebuilding the VM.

What decides that today (`openOnboardingOnFirstLaunch`, `VaultSetup`):

| State after removal | What a reinstall shows |
|---|---|
| keychain key still there, vault gone (**what `jit uninstall --purge` leaves today**) | `initialized: yes` → `.ready` → the normal panel, no onboarding |
| key gone, vault still holds secrets | `.needsRestore` → onboarding opens on **Restore**, not Welcome |
| key gone, vault gone, `onboardingShown` still set | the set-up panel, but the window never opens by itself |
| key gone, vault gone, `onboardingShown` and `setupInTerminal` cleared | **Welcome** |

`initialized` is the keychain probe alone; `secrets_stored` is the vault
directory alone. Only the last row is "the start", so all four must go.

This agrees with `onboarding.md`: "App removed and reinstalled → key and
vault persist → no onboarding. Correct." Dragging the app to the Trash keeps
everything. Remove JitPass is the one path that resets.

## 2. What JitPass puts on a Mac, and what removes it today

### Reversed by restoring a file

| # | What | Reversal that exists | Gap |
|---|---|---|---|
| 1 | Live mounts (FIFOs): `.env` family, `~/.npmrc`, `~/.netrc`, `~/.pypirc`, gcloud ADC, sops age keys, streamlit secrets, k8s secrets, loose files; pointer files and their `.pointers` companions; MCP configs | `UnmountFile`, `RestorePointerFile`, `UnwrapMCPConfig`: **current** vault values | reachable only per mount (`jit unmount`) or per project (`jit migrate remove`, one Touch ID each, fail-fast: an error leaves the project half removed) |
| 2 | Shell configs (`~/.zshrc`, `.zprofile`, `.bashrc`, `.bash_profile`, `.profile`): `export KEY=…` lines replaced by a comment and `eval "$(jit export --profile …)"` | `jit migrate undo`: the **whole file's** pre-migration bytes | **Blind overwrite, no drift check.** Every line added since is lost, including the user's own edits. The "snapshot first" safety net lives in the vault, which the purge deletes |
| 3 | Tool configs jit rewired: `~/.gitconfig` + git credential files, `~/.docker/config.json`, `~/.aws/config` + `credentials`, `~/.kube/config`, `~/.terraformrc` + `credentials.tfrc.json`, cargo config + credentials, `~/.clisso.yaml`, `terraform.tfvars`, and the ~30 CLI configs `jit wrap` scrubs a token from (`gh`, `glab`, `ngrok`, `stripe`, `vercel`, …) | `jit migrate undo`, same blind overwrite | kubeconfig, docker and git configs change often; same loss as row 2 |
| 4 | Shell history and AI-agent caches, redacted in place | `jit migrate undo` | **Should not be reversed at all**: restoring `~/.zsh_history` from the day of migration deletes every command typed since, to put a leaked token back |
| 5 | Files jit created (`~/.aws/config`, `~/.terraformrc`, cargo/git config when absent) | `RemoveOnRestore` records: undo deletes them | none |

There is no "everything": undo and remove both need a path. `jit migrate
undo ~` misses anything outside home. `LatestBackups(recs)` with no filter is
already the complete list.

### Removed, not restored

| # | What | Where | Removed today by | Gap |
|---|---|---|---|---|
| 6 | Project stores: profiles, templates | a `.jit/` in every migrated project | `jit migrate remove <project>` | `jit uninstall --purge` leaves them all; only `backups.yaml`/`mounts.yaml` know where they are |
| 7 | Vault, backups, indexes, audit and agent logs, socket, device id | `~/Library/Application Support/jitpass` | `jit uninstall --purge` | none. Logs are here, not in `~/Library/Logs` |
| 8 | **Master key**, and a staged second account if a rekey was interrupted | login keychain, service `com.jitpass.vault.mek` | `jit vault delete` (the only `DeleteMEK` caller), which refuses while any mount is live | **`jit uninstall --purge` never deletes it** |
| 9 | Global profiles, templates, shims, `wrap.json`, `guard.zsh`, the docker and git helper scripts | `~/.jit` | `jit uninstall --purge` | plain uninstall misses the two helper scripts (it only sees symlinks) |
| 10 | Helper scripts outside `~/.jit` | `~/.terraform.d/plugins/terraform-credentials-jit`, `~/.cargo/cargo-credential-jit` | **nothing, ever** | recorded nowhere |
| 11 | Shim PATH line and its comment | the login shell's rc | `jit wrap undo` of the last tool | `jit uninstall` leaves it, pointing at a deleted directory |
| 12 | History guard line and its comment | `$ZDOTDIR/.zshrc` or `~/.zshrc` | `jit guard history --remove` | `jit uninstall` leaves it (`[ -f ]` guarded, so harmless, but not "the start") |
| 13 | Background service | `~/Library/LaunchAgents/com.jitpass.agent.plist` | `jit uninstall` | none. Grants and consent answers live only in the agent's memory; stopping it erases them |
| 14 | The `jit` binary | inside `JitPass.app`, or the Caskroom | `jit uninstall` deletes `os.Executable()` | **It would delete a file inside the signed bundle or the Caskroom.** `upgrade.go` has `inAppBundle`/`brewManaged` and refuses; uninstall does not use them |
| 15 | Temp leftovers | `$TMPDIR/jit-upgrade-<version>-*` (kept on purpose by upgrade), leaked `.jit-swap-*`/`.jit-prev` siblings after a crash | nothing | small |

**A dead end today:** with secrets in the vault and the key missing,
`jit uninstall` fails at its own gate (`authorization failed … run jit vault
init first`) and removes nothing. The user who most needs to start over
cannot.

### The app's own

| # | What | Where | Notes |
|---|---|---|---|
| 16 | Preferences | `com.jitpass.app` defaults: `TerminalApp`, `EditorApp`, `BackgroundScan`, `ScanExcludes`, `NotifyDecoys`, `NotifyChanges`, `CheckForUpdates`, `LastUpdateCheck`, `OfferedCommandLineTool`, `onboardingShown`, `setupInTerminal`, `previewSetup` | the complete list; `removePersistentDomain` covers it |
| 17 | Open at login | `SMAppService.mainApp` | |
| 18 | PATH link (website installs) | `/opt/homebrew/bin/jit` or `/usr/local/bin/jit`, the latter possibly made with an admin prompt | `CommandLineTool.state` already tells "ours" from "another jit" by resolved path |
| 19 | Delivered notifications | Notification Center | nothing removes them today |
| 20 | Terminal scripts | `$TMPDIR/jitpass/jit-*.command` | each deletes itself only if it ran |
| 21 | macOS grants: Full Disk Access, notifications | TCC | `tccutil reset All com.jitpass.app` **verify** unprivileged |
| 22 | System-made leftovers | `~/Library/{Caches,HTTPStorages,Saved Application State}/com.jitpass.app*`, the preferences plist | **verify** which exist; the app creates none itself |
| 23 | The app; for Homebrew also the `jit` link and three completion links | `/Applications/JitPass.app`, `$(brew --prefix)/bin/jit`, brew's completion dirs | brew's own; `brew uninstall --cask jitpass` removes all five. The cask has **no `zap` stanza** |

The app uses no keychain, stages no update downloads, and writes no files
of its own beyond rows 16 to 20.

Not ours and never touched: copies in Time Machine or a dotfiles repo, the
1Password items that linked values point at, another `jit` on PATH that the
app did not install, a completion line the user added by hand.

## 3. Principles

1. **Plaintext is back before anything is destroyed.** All restores run,
   failures are collected, and if there is even one, nothing is deleted.
   (Not `migrate remove`'s fail-fast: that leaves a half-removed project.)
2. **Never lose the user's own edits.** A file that changed since jit
   rewrote it is either reversed line by line or, when that is not possible,
   today's version is kept beside the restored one.
3. **The plan is real and shown first.** Counts and paths come from the
   engine's dry run, not from the app's guess.
4. **Say once what it means.** Secrets go back to plain files on disk. One
   sentence, no lecture, no "are you sure" chain.
5. **A recovery file is offered, never forced.**
6. **One Touch ID, announced before it appears.** The engine gates
   uninstall on a fresh fingerprint that `--yes` cannot skip; that is the
   protection against someone at an unlocked Mac.
7. **Same commands as the CLI**, shown under "What this runs". The app
   removes only what the app installed itself (rows 16 to 22).
8. **No fake progress, and resumable.** Each step is idempotent; the next
   open reads the engine and continues.

## 4. Where it lives

Settings → General, last section, below Updates:

    Remove JitPass
    Puts every file back the way it was and removes      [ Remove JitPass… ]
    JitPass from this Mac. You see the full list first.

A plain button, not red: red belongs to the moment of commitment. It opens
its own window (620 × 540, fixed, the onboarding window's twin). The two
"in Terminal…" rows under Protection → Vault stay; they are narrower tools.

Refused while the app runs translocated (no `/AppTranslocation/` in the
bundle path), with the same "move it to Applications first" wording: the
PATH-link ownership test compares resolved paths and would be wrong there.

## 5. The flow

### Screen 1: What happens

"Remove JitPass from this Mac". Three groups, each a count with the paths
in a disclosure:

- **Goes back to plain files.** "17 files get their secrets back, readable
  by anything on this Mac, as before JitPass." When some changed since:
  "3 changed since; today's version is kept beside each."
- **Has no file to go back to.** "6 secrets live only in the vault: 2 you
  added by hand, 4 sign-ins JitPass captured." Amber: the only real loss.
- **Removed.** Vault and key, background service, protected tools (they go
  back to their own sign-in), history guard, two lines in `~/.zshrc`, the
  `jit` command, settings and permissions.

One plain line below: "Tokens JitPass cleaned out of your shell history and
AI caches stay cleaned."

### Screen 2: Keep a copy (only when group two is not empty)

Reuses onboarding's recovery step: save panel defaulting to
`jitpass-recovery-<stamp>.export`, passphrase on stdin, `jit vault export`.
Skip is a plain button of equal weight; the consequence is stated once.

The one red button, **Remove JitPass**, sits on the last screen before
work starts (this one, or Screen 1 when this is skipped), with "Touch ID
follows." beside it.

### Screen 3: Removing

Live checklist, one tick per engine step record:

1. Touch ID
2. Put 17 files back
3. Remove `.jit` from 4 project folders
4. Unprotect gh, aws and npm; remove their helpers
5. Remove 2 lines from `~/.zshrc`
6. Delete the vault and its key
7. Stop the background service
8. Settings, open at login, notifications, permissions (the app's part)

"This window stays open until it is safe to close." Quit is held, as
onboarding's protect step holds it.

### Screen 3b: Something could not be put back

"2 files could not be put back, so nothing was deleted." Path and reason per
row. Try Again, Keep JitPass, and "Remove Anyway…", which names what is lost
and offers the recovery file first. Files already restored stay restored;
Scan will list them as findings again, which is honest.

### Screen 4: Done

"This Mac is as it was." Lists what is deliberately left: the recovery
file; any "kept beside" copies; open terminal windows keep the old PATH
until closed; another `jit` on PATH if there is one.

The last step is the user's, and depends on how the app arrived:

- **Website download:** **Move to Trash and Quit**
  (`NSWorkspace.recycle` on the bundle, then terminate).
- **Homebrew** (`CommandLineTool.installedByHomebrew()`): brew owns the app,
  the `jit` link and the completions, so the step is brew's:
  `brew uninstall --cask jitpass`, selectable, with **Copy and Quit**.
  Trashing the bundle instead would leave brew's links dangling and its
  record stale. No helper, no watcher: the convention every cask app follows.

## 6. Changes

### Engine (`jitpass/jit`)

**6.1 Patch first: bugs in uninstall today.** Valuable without offboarding.

1. `--purge` deletes the keychain master key and any staged rekey account.
2. Uninstall removes the shim PATH line (`wrap.RemovePathLine`) and the
   guard (`guard.Remove`).
3. Uninstall removes the four helper scripts, including the two outside
   `~/.jit`.
4. Uninstall uses `inAppBundle`/`brewManaged` and never deletes a binary
   inside `JitPass.app` or the Caskroom; it says who owns it instead.
5. With the key provably absent (`MEKAbsent`), the gate falls back to the
   bare `keychainwrap.Challenge`, as it already does for an empty vault. A
   human is still proven present; the dead end is gone.

**6.2 `jit uninstall --restore`.** Reverses every record in the backup index
and the mount registry, under one fresh fingerprint, then purges.

| Kind | Reversal |
|---|---|
| mounts, pointer files, MCP (row 1) | existing write-back, current values |
| shell configs (row 2) | **new, line level**: the comment + `eval` pair is replaced by `export KEY='value'` lines from current vault values. Nothing else in the file moves. If the pair is gone (the user removed it), the file is left alone and reported |
| rewired tool configs, tfvars (row 3) | backup bytes. If the file's mtime is later than the migration by more than a minute, today's version is first copied beside it as `<name>.before-jitpass-removal` (it holds no jit-managed secret: jit stripped them) and listed on Done |
| history, AI caches (row 4) | not reversed; their backups are deleted with the vault |
| created files (row 5) | deleted, as undo does |

Rules: collect every failure, delete nothing if there is one, exit 2. A
symlink at a restore path is **refused**, not replaced (today undo unlinks
it silently and writes a regular file). A missing parent directory is a
failure, never `MkdirAll`'d: that is how a secret lands under an unmounted
volume's mountpoint. Then: project `.jit/` directories from the index,
rows 9 to 13, 15, and the purge.

**As built, 6.1 and 6.2:** a plain `jit uninstall` still keeps the vault so
a reinstall picks up where it left off, and for the same reason keeps the
guard and the helper scripts; only a purge removes them. The PATH line goes
on a plain uninstall only when the shim directory is empty, the rule
`jit wrap undo` follows. `--restore` implies `--purge`. Two things the dry
run on a real index taught: a migrated file that **no longer exists** (12 of
28 records pointed at deleted projects) is not recreated and not a failure,
or it would block removal forever; only a path under a `/Volumes` volume
that is not connected fails. And a secret counts as "coming back" when a
profile a restore reads names it, not only by its origin: older secrets
carry no origin and were all being reported as lost.

**6.3 For the app:** `--dry-run --format json` (the plan, including
vault-only secrets and which files drifted; read-only, no prompt) and
`--format ndjson` step records (the tracker animates only on a TTY).

Terminal wording changes with 6.1 and 6.2, so the house rule applies: a
preview script first. `jit scan` is untouched. Caller identity gates
nothing; the fingerprint is the decision.

### App (`jitpass/jit-app`)

- `OffboardingModel`, `OffboardingView`, `StatusItemController+Offboarding`;
  the section in `SettingsView.general`. The checklist reuses
  `OnboardingTaskRow`; the recovery step reuses `onboardingSaveRecovery`.
- `JitCLI.uninstallPlan()` and a streaming `uninstall(onStep:)` shaped like
  `scan(onLines:)`, with its pid registered in `JitCLI.spawned` so the
  consent sheet lets it through.
- The app's own step, only after the engine exits 0: deny pending consent
  requests, `SMAppService.mainApp.unregister()`, remove the PATH link when
  `CommandLineTool.state` says `.linked` (admin prompt if that is how it was
  made), `removeAllDeliveredNotifications`, remove `$TMPDIR/jitpass`,
  `tccutil reset All com.jitpass.app`, `removePersistentDomain`, remove
  row 22.
- `scripts/cask.sh` gains a `zap trash:` stanza for rows 7, 9, 13, 16, 22, so
  `brew uninstall --zap` means something. Zap restores no files; the caveat
  says to use Remove JitPass first.
- `AgentOp` gains nothing. The app calls only what the CLI can run.

## 7. Phases

0. **Verify on the VM**: `tccutil` unprivileged; which row 22 paths exist;
   a running bundle trashes and quits cleanly; `brew uninstall` after the
   engine is gone.
1. Engine 6.1, released as a patch.
2. Engine 6.2 and 6.3.
3. App flow and the cask `zap`; bump `jit.version`; release.
4. **The acceptance loop**, scripted: snapshot (checksums of every file
   onboarding will touch and the rc files, `launchctl list`, a keychain
   query for `com.jitpass.vault.mek`, `defaults read com.jitpass.app`,
   listings of `~/.jit`, `~/Library`, `~/.terraform.d/plugins`, `~/.cargo`)
   → onboard → offboard → snapshot → the diff is empty → reinstall →
   onboarding opens at Welcome.

## 8. Edge cases

- **Vault locked or service down**: the engine does its own fresh auth; the
  app starts nothing first.
- **Key gone (`needsRestore`)**: nothing can be decrypted, so nothing can
  be restored. Screen 1 says so and offers Restore first. "Start Over"
  removes everything anyway (6.1.5 makes that possible) and lists the
  pointer files and dead mounts the user must fix by hand. The one path
  that deletes without restoring, and its button says so.
- **A rekey in progress**: the engine refuses (`errRekeyInProgress`); the
  app says "finish or cancel the key rotation first".
- **Values changed since migration**: current values win for rows 1 and 2.
  Row 3 files get the value from migration day and are flagged in the plan.
- **Captured SSO sessions and wrap tokens**: no file to return to; the
  tools ask for their own sign-in again.
- **1Password-linked values**: row 1 and 2 write-back resolves the link, so
  the file gets the real value; nothing in 1Password changes. **verify**
  this costs one `op` authorisation, and announce it if so.
- **A live mount being read, a `jit run` in flight**: exec'd processes keep
  their environment; mounts stop one at a time as each file is restored.
- **Open shells** keep the shim PATH and the loaded guard until they exit.
  The guard fails open when `jit` is missing.
- **Another jit on PATH** the app did not install: left alone, named on
  Done with `jit uninstall`.
- **Pre-index backups** (very old builds) are in no index and cannot be
  found; the plan cannot list them. Stated in the disclosure, not hidden.
- **Closed mid-way or a crash**: vault still there → normal panel, Remove
  runs again and skips what is done. Vault gone, app leftovers present →
  the app finishes its own step and shows Done.
- **Other macOS users**: untouched; all of this is per user. The bundle is
  shared, which Trash and brew already handle the usual way.

## 9. Decisions (2026-09-18)

1. **Files are always restored.** No "leave them as they are": that leaves
   dead FIFOs that hang whatever reads them.
2. **The app's own removal** is the user's last click: Move to Trash and
   Quit for a website install, the brew line with Copy and Quit for a
   Homebrew one. No helper process.
3. **The recovery screen appears only when vault-only secrets exist.**
4. **It is called "Remove JitPass".**
5. **Engine 6.1 ships first as its own jit patch.**

Added by the audit:

6. Shell history and AI caches are **not** restored (row 4).
7. A drifted tool config is restored and today's version kept beside it,
   rather than refusing or overwriting silently (6.2).

Both confirmed 2026-09-18 ("ok lets do it").

## 10. Where each claim was read

`internal/cli/uninstall.go:124-180,209-241` (gate, purge, binary removal);
`internal/cli/vault.go:2446-2530` (`vault delete`, the only `DeleteMEK`);
`internal/keychainwrap/keychainwrap.go:55,219-228,317`, `rekey.go:45`;
`internal/cli/status.go:382,412` (`initialized` = key probe);
`internal/migrate/undo.go:225-250,292-379` (`LatestBackups`, blind restore);
`internal/migrate/shellconfig.go:39,229-244` (the rc rewrite);
`internal/cli/migrateremove.go:392-439` (fail-fast);
`internal/mount/retire.go:53-63` (symlink unlinked);
`internal/wrap/pathenv.go:48-103`, `internal/guard/guard.go:221-313`;
`internal/migrate/terraform.go:71`, `cargocreds.go:80`, `dockercreds.go:80`,
`gitcreds.go:173` (helper scripts); `internal/cli/upgrade.go:74-98,501`;
`internal/agent/grant.go`, `internal/consent/consent.go:58-73` (memory only).
App: `StatusItemController+Onboarding.swift:40-75`, `VaultSetup.swift:23-33`,
`MenuModel.swift:121-145`, `CommandLineTool.swift:24-69`,
`StatusItemController+Updates.swift:165-220`, `Notifier.swift:37-53`,
`Terminal.swift:78-99`, `Translocation.swift:15`, `scripts/cask.sh:18-59`.
