# The Vault window

Status: phases 1 and 2 built 2026-09-17 (`VaultView`, `VaultSheets`,
`StatusItemController+Vault`, `JitAgentClient/VaultListing` and
`SecretBuffer`). Phase 3 built the same day: a Maintenance sheet off the
sidebar footer (`VaultMaintenanceSheet`, `StatusItemController+VaultMaintenance`,
`JitAgentClient/VaultOrphans`) with orphans listed by origin and pruned
after a dialog, backups pruned, export and import with the passphrase on
stdin, rekey, and duplicates in-app too (`VaultDuplicatesSheet`, the
report as blocks with the CLI's verdict and command, Prune for the stale
copies only); Settings › Protection gained the Vault section with clean
and delete as terminal buttons. The consent sheet lets a jit process the
app itself spawned through to the Touch ID without asking again
(`JitCLI.spawned`): the app's own dialog was the question. Doctor's own
prune and export actions stay where they were. The engine's `used_by`
shipped in jit 1.6.2: the selection bar shows "used by wrap-gh, dev-api"
and the Delete dialog warns before the confirmation.

`design/menu-bar-app.md` (jit repo) says the app is "not a vault browser"
in v1: names, states and events only, never a value. v0.9.2 honours that so
strictly that the panel's Vault row is the only vault surface at all: it reads
"67 secrets" and opens nothing. Every vault operation is a terminal trip.

This proposes the next step: a Vault window that lists, adds, replaces,
links, restores, reveals, copies and deletes secrets, and runs the
maintenance commands. The v1 rule "never a value" becomes "**a value only
after its own Touch ID, on screen for ten seconds, and never kept**". Section
3a says exactly what "never kept" can and cannot mean in a Swift process.

## 1. What the engine offers

Every command below is jit 1.5.8. "Gesture" is the fresh Touch ID/passcode
the CLI demands itself, independent of the service session; the app cannot
and must not bypass it. "Asks" is a typed y/N the CLI stops for, which a
spawned process cannot answer, so the app passes `--yes` only after its own
dialog has asked the same question.

| Command | Does | Gesture | Asks | `--format json` | App |
|---|---|---|---|---|---|
| `list` | paths + class, group, origin, storage, timestamps; `--all` adds `_backups/` | no | no | yes | in-app, the window's data source |
| `history <p>` | archived versions (stamp, created, updated); newest 5 kept | no | no | yes | in-app |
| `orphans` | secrets no visible profile references, stale mount registrations | no | with `--prune` | yes | in-app list; prune after a dialog |
| `set <p> --stdin` | store a value read from stdin; overwrite asks | yes | on overwrite | – | in-app (Add, Replace) |
| `link <p> op://… ` | store a 1Password reference; verifies through `op` | yes | on overwrite | – | in-app, see 1Password note |
| `get <p> --copy` | decrypt to the clipboard, auto-clear | yes | no | – | in-app (Copy), value never enters the app |
| `get <p>` | decrypt to stdout; piped, the value alone, no footer | yes | no | yes | in-app (Reveal), see 3a |
| `restore <p> [--version s]` | move an archived version back, current archived first | yes | no | – | in-app from History |
| `rm <p>…` | delete secrets; a bare group name expands to the group | yes | yes | – | in-app after a dialog listing the paths |
| `prune` | delete every backup but the newest per file | yes | yes | – | in-app (already a doctor action) |
| `orphans --prune` | delete the orphans | yes | yes | – | in-app |
| `export <file> --stdin` | passphrase-encrypted backup | yes | no | – | in-app (already a doctor action) |
| `import <file> --stdin` | restore from an export, overwrites same paths | yes | yes | – | in-app |
| `rekey` | new master key, re-wrap everything | yes | yes | – | in-app after a dialog |
| `duplicates` | compares every decrypted value; one gesture plus one consent per class | yes, several | with `--prune` | yes | **terminal**, like `jit scan --full` |
| `clean` | delete every secret, keep the key | yes | yes | – | **terminal only** |
| `delete` | destroy the vault and its key | yes | yes | – | **terminal only** |
| `init` | create the vault | – | – | – | doctor already handles a missing vault |

Facts that shape the design:

- **Touch ID works from a spawned jit.** `JitCLI.execute` already relies on
  it for doctor actions. Only typed prompts (y/N, hidden input) do not, hence
  `--yes` and `--stdin`.
- **`--stdin` reads the whole input and trims trailing newlines**, so a
  multi-line value (a PEM key) round-trips. The value travels through a pipe,
  never through `argv`, so it is never visible in `ps`.
- **`list` and `history` are prompt-free** because they read envelope
  headers only. The window can refresh after every operation at no cost.
- **Which profiles use a secret is not in the JSON today.** The CLI computes
  it prompt-free for `get`'s footer and `rm`'s warning, from profile
  manifests. The one engine change this design asks for is a `used_by`
  array on each `list --format json` record, so the Delete dialog can say
  "used by profile dev-api" before the user confirms. Without it the app
  shows `rm`'s own warning text after the fact, which is acceptable for
  phase 2 but weaker.
- **Group is the unit users think in.** 67 secrets on this Mac fall into
  groups by first path segment, each with one origin file. The CLI's own
  `list` groups the same way, and `rm <group>` deletes a group in one
  gesture.
- **A 1Password link is a secret with `storage: "op-ref"`.** One of the 67
  here is. `link` test-resolves the reference through the `op` CLI, which
  the app's spawned process may not find on its minimal PATH. The sheet
  therefore offers "verify through 1Password" as a checkbox that is on when
  `op` is found and off with an explanation otherwise, mapping to
  `--no-verify`.

## 2. Where it lives

- **Panel.** The Vault row becomes a button, like Grants and Doctor, and
  reads `67 secrets · 1 linked` when a link exists. Nothing else changes on
  the panel; vault is a window, not a panel section.
- **Window.** `VaultView` in a `ReportWindow`, the same shell as Grants,
  Audit and Scan. Same header pattern: title, one-line summary, buttons.
- **Settings.** A new Vault section with the two commands that destroy
  everything, each a button that opens the terminal with the command
  prefilled, because jit's own confirmation should be the last word there.

## 3. The window

Two panes, the shape Keychain Access and 1Password use: profiles on the
left, the selected profile's secrets as a table on the right, one bar under
the table for the selected secret. A first draft was a single grouped list
of every row with hover actions; at 67 secrets the detail text floated at
whatever width the name left and nothing lined up, and it had no idea of a
profile at all.

```
┌───────────────────────┬──────────────────────────────────────────────────────┐
│ 67 secrets · 1 linked │  aws-prod                  [Add…] [Link…] [Delete…]   │
│ [filter          ]    │  4 secrets · from ~/.clisso.yaml                      │
│                       │                                                       │
│ ● aws-prod         4  │  NAME                CLASS   UPDATED                  │
│ ● aws-stage        4  │  ACCESS_KEY_ID       aws     4 weeks ago              │
│ ● claude-inventory 8  │  EXPIRATION          aws     4 weeks ago              │
│ ○ old-proj         3  │  SECRET_ACCESS_KEY   aws     4 weeks ago              │
│   stripe           2  │  SESSION_TOKEN       aws     4 weeks ago              │
│   …                   │                                                       │
│                       │  ── SECRET_ACCESS_KEY ─────────────────────────────── │
│ 170 migrate backups   │  [Reveal] [Copy] [Replace…] [History…]     [Delete…]  │
└───────────────────────┴──────────────────────────────────────────────────────┘
```

- **Sidebar = profiles.** A "profile" here is the first path segment: what
  `jit vault list` groups by and `jit vault rm <group>` deletes by, and in
  practice one migrated file. Each row carries a count and a dot: green
  when the recorded origin file still exists, amber when it is gone (the
  shape `orphans` and `duplicates --prune` care about), none for hand-set
  secrets. The filter narrows the sidebar by profile, name or origin.
- **Detail header = the facts once.** The origin file, or "set by hand",
  and the profile's actions: Add and Link default to this profile; Delete
  Profile lists every path before it runs.
- **Table = aligned columns.** Name (with a chain glyph for a 1Password
  link), class, updated. Sortable headers and keyboard selection come with
  the control.
- **Selection bar = one place for actions.** Reveal, Copy, Replace,
  History, Delete for the selected row, also on its context menu. The
  revealed value and its countdown appear in this bar, so the table never
  reflows. Changing the selection hides a reveal.

Engine gap this exposes: `jit status --format json` has only totals for
wired groups, so "served by mount" and a wiring-based dot need a per-group
answer the CLI does not give yet. The dot is origin-exists for now.

### Sheets

**Add** (`vault set <path> --stdin`). Fields: profile (an `NSComboBox`
over the existing names, free text allowed, defaulting to the selected
profile), name, value. The value field is a
`SecureField` with a "multi-line" toggle that swaps in a plain text editor
for keys and certificates; the toggle is the one place the typed text is
visible, and it is text the user is typing, not a stored value. Footer text:
"Touch ID follows." On an existing path the sheet's button reads Replace and
the command gains `--yes`, after the sheet itself has shown "replaces the
current value; the old one is kept in history".

**Replace…** on a row is Add with group and name fixed.

**Link 1Password** (`vault link <path> <op://…> [--no-verify]`). Path fields
as Add, a reference field validated as `op://vault/item/field`, the verify
checkbox described above. Footer explains the two prompts jit's help
describes: jit's Touch ID, then 1Password's own dialog.

**History…** (`vault history --format json`, then `vault restore --version`).
A list of archived versions, newest first, each "archived 3 days ago, value
from 2026-08-02", with a Restore button per row. Restore confirms in a plain
alert ("the current value is archived first, so this is reversible") and
runs with the stamp. No `--yes` exists on restore and none is needed.

**Delete…** (`vault rm <path>… --yes`). First `vault rm --dry-run --format
json <paths>` (jit 1.9+, prompt-free), then one alert worded from it: the
exact paths it will remove and, from the engine's strict collector (every
project store under ~, every mount, every pointer file, not the listing's
`used_by`), each profile or pointer file still using them, with its
launchers and what stops starting. Nothing in use: "Delete", running
`rm --yes <paths>`. In use, or jit can't tell: a different button, "Delete
and Break <profile>" (or "Delete Anyway"), running `rm --break-profiles
--yes <paths>`, with Cancel the default. A dry run that fails (a jit older
than 1.9) deletes nothing and says why. The paths are the dry run's
expansion, not a group name, so what the dialog listed is exactly what
runs; a refusal in the gap between the two shows jit's own output, which
names who uses them.

**Copy** (`vault get <path> --copy`). No sheet. The row shows "Touch ID…"
while jit prompts, then "copied, clears in 45s" from jit's own output line.
The app reads that line, never the value. jit writes the pasteboard with
`org.nspasteboard.ConcealedType`, so clipboard managers skip it.

**Reveal** (`vault get <path>`, stdout piped). No sheet. The row shows
"Touch ID…", then the value replaces the row's class and age in a
monospace field for ten seconds with a countdown ring, then the row returns
to normal. A second click during the countdown hides it early. The value
is also hidden, and wiped, when the window closes, the app resigns active,
the screen locks or the panel opens. The field is not selectable: Copy is
the way to copy, because it never routes the value through the app. Every
Reveal is its own Touch ID; there is no "unlocked for a minute" state.

### 3a. Reveal and memory

What Swift can and cannot promise was checked before this was written
(Apple DTS on the developer forums, thread 4879; 1Password's post on local
threats; a compiled check of the two APIs below under `-O`).

- **A `String` cannot be wiped.** Its storage is a heap block the code has
  no handle to, and every framework it touches may copy it. Apple's own
  engineer calls scrubbing "infeasible" once high-level APIs are involved.
  1Password says the same in different words: they minimise and attempt to
  clear, and cannot guarantee it.
- **Bytes the app owns can be.** `Data.resetBytes(in:)` overwrites a
  `Data`'s own storage, and `memset_s` (C11, in the macOS SDK) overwrites a
  raw buffer and cannot be dropped by the optimiser as a dead store. Both
  compile and behave in this toolchain.

So the design is honest about which copies exist and wipes the ones it can:

1. `JitCLI.reveal(_ path:)` reads the pipe into a `Data` and hands it to a
   `SecretBuffer`, a small final class over an `UnsafeMutableRawBufferPointer`
   whose `wipe()` calls `memset_s` and whose `deinit` wipes and frees. The
   `Data` from the pipe is `resetBytes` immediately after the copy. jit's
   stdout carries the value alone (the footer goes to stderr, and only on a
   terminal), so nothing has to be parsed and no JSON decoder makes copies.
2. The row renders a `String` made from the buffer for the countdown. That
   `String`, and whatever the text system copies for layout, are the copies
   the app cannot wipe. They are dropped when the countdown ends and freed
   by the allocator; macOS zeroes a page before another process can get it.
3. The buffer is wiped on every hide path listed above, not only on the
   timer, and the model holds at most one buffer at a time.
4. Nothing is logged or cached. `MenuModel.vaultReveal` holds the display
   `String` for the countdown, because the view has to render it from
   somewhere, and is nil the moment the reveal ends. It is the one place a
   value ever sits in the model, and it never outlives the ten seconds.

What bounds the residual risk is the process boundary, not the wipe: the
app is signed with the hardened runtime and no `get-task-allow`, so another
process cannot read its memory without root and a disabled SIP, macOS has
encrypted swap on by default, and the app does not write core dumps. That
is the same posture jit itself has while it prints the value, and the same
one 1Password ships with. A ten-second window in a hardened process is a
deliberate, bounded exposure, not a leak.

### Maintenance

- **Orphans** opens a sheet listing `orphans --format json` with each
  secret's origin and the stale mounts, and a Prune button that runs
  `orphans --prune --yes` after an alert listing the paths.
- **Backups** runs `prune --yes` after the destructive dialog. Doctor's
  existing prune action moves here and doctor links to it.
- **Export** is doctor's existing flow (save panel, passphrase sheet,
  `export --stdin`) lifted into a shared helper. **Import** is its mirror:
  open panel, passphrase field, an alert saying same-path secrets are
  overwritten, then `import --stdin --yes`.
- **Rekey** runs `rekey --yes` after an alert quoting the help: safe to
  interrupt, re-running finishes it.
- **Duplicates** opens the terminal with `jit vault duplicates`. It asks for
  several gestures and a consent per class, and its report is long and
  advisory; a window would reproduce the whole thing for no gain.

## 4. State and plumbing

- `JitAgentClient` gains `VaultListing` (`secrets`, `backups`) and
  `VaultSecret` decoded from `list --all --format json`, `VaultHistory`
  from `history --format json`, `VaultOrphans` from `orphans --format json`.
  Derived: `group`, `name`, `isLinked`, `age`, `versions` (from a history
  call made lazily when a row is expanded, never for the whole list).
- `MenuModel` gains `vaultListing`, `vaultOrphans`, `vaultBusy: String?`
  (the row or action waiting on a gesture) and `vaultMessage` for the last
  failure, mirroring `doctorRunning` / `doctorMessage`.
- `JitCLI.vaultList()`, `vaultHistory(_:)`, `vaultOrphans()` follow
  `scan(path:)`: `--quiet`, decode, throw on failure. Writes go through the
  existing `execute(_:stdin:)`.
- `StatusItemController+Vault.swift` owns the window, the sheets and one
  `runVault(_ argv:, stdin:, then:)` that sets `vaultBusy`, runs off the
  main thread, clears it, refreshes the listing and `status`, and surfaces a
  failure under the header. One operation at a time, like doctor.
- After any write the panel's Vault row and the Protected row both refresh:
  a replace does not change coverage, but a delete of a migrated secret
  does, so the scan is marked stale the way Protect already does.

## 5. Rules

1. A value appears only after its own Touch ID, only in the Reveal field,
   only for ten seconds, and the app wipes every copy it owns when it goes.
   Never in a tooltip, a log, a cache, or the model.
2. `--yes` is passed only after an app dialog that names exactly what runs.
   The fingerprint is never the app's to skip, and no command here can.
3. Values reach jit through stdin, never `argv`.
4. `clean` and `delete` are terminal buttons in Settings and nowhere else.
5. The window reads only prompt-free commands on open and refresh. A window
   that triggers Touch ID on open would be the folder-prompt mistake again.

## 6. Phases

1. **Browse.** Panel row opens the window; listing, filter, groups, history
   sheet read-only; maintenance rows show counts with Open in Terminal.
   No engine change.
2. **Write.** Add, Replace, Link, Reveal, Copy, Restore, Delete, group delete.
   Engine: `used_by` on `list --format json` records, then the Delete dialog
   names profiles. Release order: jit first, app pins it.
3. **Maintenance.** Orphans sheet, prune, import, export moved from doctor,
   rekey. Settings gains the Vault section with clean and delete.

When phase 2 ships, `design/menu-bar-app.md`'s "not a vault browser" line
is rewritten to say what is now true: the app shows a value only after its
own Touch ID, for ten seconds, and keeps none.

## 7. Decisions still open

- **Reveal.** Decided 2026-09-17: in, ten seconds after Touch ID, on the
  terms in 3a.
- **`used_by` in the engine now or later.** It is small (the function exists
  in `vaultrefs.go`) and it is the difference between a Delete dialog that
  warns and one that does not. Recommendation: do it with phase 2.
- **Where duplicates goes.** Terminal, as proposed, or a window in phase 3
  once its JSON has a stable shape.
