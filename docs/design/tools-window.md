# Tools, guards and AI agents

Status: built 2026-09-17 through phase 2 on branch `tools-window`, against
jit 1.6.1 (branch `native-wrap-home`: `wrap list --discover`, the native
delegation's home-path fix). Revised the same day after use: **two windows,
not one**. "AI Agents" got its own window laid out as the website's
"ai agents" page (agents, what they read and grants, cached copies, MCP
configs, limits); "Tools" lists tools only. Every button runs in-app except
renewing an SSO session, which is the IdP's MFA prompt. Rows answer "is
there a key" before "did jit wrap it" (§3, key states).

jit protects a credential in three modes: it stores it (the vault), it
delivers it just in time (`run`, grants, mounts, and `wrap`'s shims), and it
prevents it being recorded at all (`guard`). The app shows the vault, grants,
mounts, scan and doctor. It shows nothing of the shims, nothing of the guard,
and it does not say what jit does about AI coding agents, which is the
question users ask first. On this Mac today: clisso is wrapped and catches
every AWS login into the vault, the zsh history guard is installed, the
`aws-stage` session has expired, and gh, claude and cursor-agent are
installed but still keep their tokens in plaintext. None of that is on
screen.

This adds an **AI Agents row** on the panel, a **Tools window** for wraps,
native protections and captured sessions, a **guard toggle** in Settings,
and an **AI agent caches** section in the scan window. "AI agent protection"
is three engine features wearing one name, and the row is where the app says
so in one line.

## 1. What the engine offers

"Gesture" is a fresh Touch ID the CLI demands itself. "Asks" is a typed y/N a
spawned process cannot answer, so the app may pass `--yes` only after its own
dialog asked the same question. Nothing below is a socket op; every column is
a CLI call, like the Vault window.

| Command | Does | Gesture | Asks | `--format json` | App |
|---|---|---|---|---|---|
| `wrap list` | wrapped tools from `~/.jit/wrap.json`: kind, what each injects, shim present or missing | no | no | **no** (text table) | the window's data source, once JSON exists |
| `wrap <tool>` (catalog, shim kind) | find the tool's token (config file or `gh auth token`), vault it at `wrap-<tool>/VAR`, install the shim, scrub the file after an encrypted backup, add the PATH line to the rc file | yes, when a token is found | no | – | in-app (Wrap sheet) |
| `wrap <tool>` (capture kind: clisso) | install the shim that routes each login through `jit clisso-capture`; move the OneLogin client-secret out of `~/.clisso.yaml` | yes, if a client-secret is found | no | – | in-app |
| `wrap <tool>` (native kind: aws, terraform, docker, git) | delegates to `jit migrate --only <category>`, no shim | yes | yes (migrate's) | – | in-app (Protect dialog, then `jit migrate --only <category> --yes`) |
| `wrap <tool>` (run-grant kind: kubectl) | shim only, no token | no | no | – | in-app |
| `wrap add <tool> --env VAR=<path>` | wrap any tool by hand | no | no | – | in-app (Repair, and the hand-wrap form) |
| `wrap undo <tool>` | remove shim and wrap profile, keep the vault secret; drop the PATH line when the shim dir is empty | no | no | – (`--dry-run` is text) | in-app after a dialog |
| `doctor --wrap` | shim dir mode, PATH, rc line, per-tool symlink/target/binary/profile | no | no | yes, **problems only** | already in Doctor; not a listing |
| `guard history` / `--remove` | install or remove the zsh `zshaddhistory` hook and its rc line | no | no | – | in-app (Settings toggle) |
| `status` | `guard.installed`, and `sessions[]`: the captured temporary credentials with `expires_unix`, `live`, `remaining_seconds`, `mint` | no | no | yes | in-app, already fetched |
| `scan` | `agent_cached_secret` findings: a confirmed credential's verbatim copy in an agent cache, with `origin_path`; agent credential stores (Cline, OpenCode, Copilot) as ordinary findings with "found in X's local store" evidence | no | no | ndjson | in-app, already parsed |
| `migrate caches` | decrypt the whole vault, find every copy in every agent cache, redact in place with a backup; binary stores are reported, not rewritten | yes, its own | yes | – (`--dry-run` is text) | terminal in phase 1, in-app in phase 3 |

Facts that shape the design:

- **The catalog is the map of what "wrap" means.** 37 entries in four kinds:
  31 shim tools that read a token from an env var, one capture tool
  (clisso), four native tools (aws, terraform, docker, git) that jit hooks
  through the tool's own credential mechanism, and one run-grant tool
  (kubectl). Each entry carries a one-line `Doc` ("GitHub CLI OAuth token"),
  the env var, where the plaintext lives today, and a `VerifyHint`
  ("gh auth status"). The window can be built from this data alone; nothing
  in the app knows a tool by name.
- **Eight catalog entries are AI coding agents**: claude, gemini, codex,
  cursor-agent, copilot, cline, opencode, kiro-cli. Wrapping one moves its
  API key out of a config file into the vault and injects it only into that
  agent's process. This is the "protect my AI agent" the user is asking
  about, and it is ordinary shim wrapping with a heading over it.
- **Discovery can fail honestly.** For a tool with no token on disk and
  nothing in the vault, `jit wrap gh` installs the shim anyway and says to
  `jit vault set wrap-gh/GH_TOKEN`. The CLI cannot take the value in the
  same step; the app can, because it has a field and `vault set --stdin`.
  That one sheet is the strongest reason to do wrapping in-app.
- **Shim kind and capture kind never ask y/N.** Only the native kind does,
  through migrate, and migrate takes `--yes` and its own Touch ID from a
  spawned process. So native tools get an in-app Protect: a dialog that says
  what migrate will move and back up, then `jit migrate --only <category>
  --yes`, one gesture, and migrate's result text in a sheet. The scan
  window's Protect button still runs migrate in the terminal today; it
  should move to the same dialog in phase 2 so there is one migrate path.
- **Health lives in two places and JSON in neither.** `wrap list` says
  "ok" or "missing" per shim, as text. `jit doctor --format json` reports a
  broken shim under `kind: "wrap"` and an environmental one under
  `kind: "wrap_env"`, but a healthy tool appears in no JSON at all. The one
  engine change this design needs is `jit wrap list --format json` carrying
  what the text table and `wrap.Doctor` already compute: per tool, kind,
  doc, injected vars with their vault paths and whether each is stored, the
  shim verdict, and the real binary's path. With `--all`, the catalog
  entries that are not wrapped, so the app can say "installed, not wrapped".
- **The app's own PATH never has the shim dir.** `JitCLI.environment`
  prepends Homebrew only, so a doctor run from the app always reports "shim
  dir not on PATH in this shell" once anything is wrapped. The app maps that
  to "Wrapped tools, this shell only", which is accurate and useless. The
  fix is one line: put `~/.jit/shims` on the app's PATH too, so that check
  describes the user's shell rather than the app's.
- **Captured sessions are wrap's visible result.** `status.sessions` lists
  `aws-prod` (live) and `aws-stage` (expired, "clisso get stage" mints a new
  one). The Vault window already decodes `expires_unix` and shows nothing
  for it. These belong under the clisso row: "catches AWS logins · aws-prod
  live · aws-stage expired 2 hours ago".
- **Minting needs a terminal.** `clisso get stage` runs the IdP's MFA prompt
  in the user's terminal; that is the whole point of the capture kind. The
  app offers "Mint in Terminal", never runs it itself.
- **Guard state is one boolean, already fetched.** `guard.Installed` is true
  only when the hook file exists and the rc file sources it with a live
  line, so a commented-out line reads as off. Install and remove are
  prompt-free and instant. Shells already open keep whatever they loaded; the
  CLI says so and the toggle's note must too.
- **Agent caches are a scan finding type, not a wrap.** `agent_cached_secret`
  inherits severity from the credential it copies, carries `origin_path`, and
  is always `remedy: "manual"` because the scan cannot promise a later
  migrate reaches every copy. The scan window today lists these among "only
  you can fix" rows by file path, so a user sees `~/.claude/file-history/…`
  with no idea why. The report already names the category "AI Agent Caches";
  the app should too.
- **Consent already covers agents at run time, and wrap is deliberately
  outside it.** The consent engine gates vault classes that are machine
  credentials (aws, docker, git, kube, gcp, 1password, …) and explicitly
  excludes the `wrap` class: a shim token is delivered to the one tool the
  user wrapped, which is consent enough. So a wrapped `claude` never raises
  the Asking sheet, and a design that promised "ask before each AI agent's
  credential use" would be wrong. What the sheet does catch is an agent
  reaching for a machine credential through jit: Claude Code running `aws`
  or `git push` shows "claude → aws" with the launcher named. That is the
  protection worth pointing at, and it exists.

## 2. Where it lives

- **Panel.** Two new rows after Vault, both buttons like Vault and Grants.

  ```
  ◐ AI Agents    3 installed · 1 protected
  ○ Tools        1 wrapped · 3 to wrap
  ```

  **AI Agents** opens the Tools window on its AI agents section. Its dot
  is the honest summary of three facts the engine already knows per
  installed agent (section 5): the agent's own key is wrapped, the last
  whole-Mac scan found no copies of the user's secrets in that agent's
  caches, and consent is on. Green when every installed agent has all
  three; red when a scan found cached copies, because that is a live
  leak; amber when an installed agent is unwrapped or consent is off;
  none when no agent is installed. The value reads `3 installed ·
  1 protected`, or `caches hold 9 copies` when red, since the number is
  what makes someone click.

  **Tools** opens the Tools window. One fact, the most urgent: `1 expired`
  (a captured session ran out), else `1 to protect` (a key in a plaintext
  file), else `1 wrapped`. The dot says which. Dot: green when every wrapped tool's shim is healthy, red
  when one is broken, none when nothing is wrapped. An unwrapped tool is
  not amber here; the count says it and this row should not nag. When a
  captured session has expired the value reads `1 wrapped · aws-stage
  expired`, because that is the one state a user needs before their
  morning's first `aws` call fails.
- **Tools window.** `ToolsView` in a `ReportWindow`, 760×480. One list of
  the non-agent tools jit knows on this Mac, a selection bar below like
  the Vault window's. Header: "8 of jit's 37 tools installed here · 1
  wrapped", a denominator so the count reads as "of what jit can wrap",
  not an inventory.
- **AI Agents window.** `AgentsView`, 720×600, scrolling sections in the
  website's order: one card per installed AI CLI with its three facts as
  three lines (key, caches, reach), each with its button; "what agents
  read" (mounts serving decoys, active grants, New Grant…); "copies the
  agents already made" (cache groups, Clean Caches…); "MCP servers"
  (findings per config file, Protect… runs `jit migrate <file> --yes`);
  and one line on what none of it covers. Ten AI CLIs count as agents
  (the page's list: claude, codex, gemini, cursor-agent, copilot, cline,
  opencode, kiro-cli, openai, hf); eight of them keep caches the scanner
  knows by name. A first try put the agents as a section of the Tools
  window with two panel rows opening it; from the panel that read as two
  features landing in one list, and the compressed "no key found · caches
  clean" row had no room to explain either fact.
- **Settings.** A new **Shell** section with the history guard toggle. Not
  the Tools window: the guard is a machine-wide preference with no rows.
- **Scan window.** Agent-cache findings get their own heading, "AI agent
  caches", grouped by agent and area ("Claude Code · edit history · 9
  copies of STRIPE_SECRET_KEY from ~/proj/.env") with one "Clean Caches…"
  button, instead of nine file rows under "only you can fix".
- **Vault window.** Captured secrets (`class: "aws"` with `expires_unix`)
  show "expires in 2h" or "expired" in the detail line. Small, and it stops
  the two windows disagreeing.

## 3. The window

```
┌ JitPass Tools ──────────────────────────────────────────────────────┐
│  8 tools jit knows on this Mac · 1 wrapped                [Refresh] │
│                                                                     │
│  AI AGENTS                                                          │
│  ○ claude        Anthropic API key for Claude Code   key in a file · 9 cached copies  [Wrap…] │
│  ○ cursor-agent  Cursor CLI API key                  key in a file · caches clean     [Wrap…] │
│                                                                     │
│  TOOLS                                                              │
│  ● clisso        AWS logins via OneLogin/Okta         catching   [Unwrap…]  │
│  ○ gh            GitHub CLI OAuth token               not wrapped [Wrap…]   │
│  ● aws           served through credential_process    protected             │
│  ● git           served through a credential helper   protected             │
│  ○ docker        registry logins                      not protected [Protect…] │
│  ○ kubectl       migrated Secret manifests            not wrapped  [Wrap…]  │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│  clisso · catches every `clisso get` into the vault                 │
│  aws-prod   live                                                    │
│  aws-stage  expired 2 hours ago             [Mint in Terminal]      │
│  Shim ok · verify: clisso get <app>, then aws sts get-caller-identity│
└─────────────────────────────────────────────────────────────────────┘
```

- **Rows** are catalog tools whose real binary is installed, plus any
  hand-wrapped tool from the manifest. Catalog tools that are not installed
  are not listed; the header's "jit knows" count is what is on this Mac.
  Dot: green wrapped and healthy (or native and migrated), red wrapped and
  shim broken, grey not wrapped. The second column is the catalog `Doc`,
  reworded only where it says "for the X CLI" twice.
- **AI agents** is the first section whenever one is installed. Same rows
  and buttons as a shim tool, plus a second state phrase for the caches
  ("9 cached copies" / "caches clean" / "not scanned yet"), and the
  selection bar shows the three facts as three lines with their own
  buttons: key (Wrap… / Show in Vault), caches (Clean Caches… / Scan Now),
  consent (on, or Off with a Settings link). Two dots would be a lie of
  precision; the row's dot is the worst of the three, the bar shows each.
- **Key states, before state words.** "not wrapped" says what jit has not
  done, not whether there is anything to do; a user seeing claude "not
  wrapped" asked whether they even had a key. So each unwrapped row first
  answers that, from two sources: `jit wrap list --discover` (the wrap
  flow's own discovery, config files then the tool's export command,
  reporting where and never what) and the last whole-Mac scan (a finding
  whose fix is `jit wrap <tool>`, a shell export whose key name is the var
  the tool reads, a credential file in a native tool's directory). Four
  states: **protected**; **found** at a place, "key in ~/.zshrc" (amber, a
  plaintext file, counted as "to protect") or "token in gh's keychain"
  (grey: encrypted at rest, wrapping is an improvement, not a fix);
  **none** found ("no key found" / "nothing found", grey, no Protect
  button since migrate on nothing only answers "Nothing to migrate");
  **not checked** (no discovery and no scan). Wrapped rows say "wrapped"
  / "catching" / "shim missing" / "shim broken"; native ones "protected".
- **Selection bar**, per kind:
  - Shim: "injects GH_TOKEN from wrap-gh/GH_TOKEN" with "Show in Vault",
    which opens the Vault window on that group; "Verify in Terminal" runs
    the catalog's hint. A wrapped tool whose vault path is empty reads
    "wrapped, nothing stored yet" with "Store…", the Add sheet prefilled.
  - Capture: the sessions from `status.sessions`. A session with no
    expiry stamp reads "no expiry recorded · the next login stores one",
    not "live", because jit reports it live only for want of a stamp. An
    expired one reads "expired yesterday · `clisso get stage` renews it"
    with "Renew in Terminal": a fresh login with the user's MFA, caught
    into the vault. "Mint" is jit's word and stays in the CLI.
  - Native: "aws SDKs and the CLI read it through credential_process";
    no buttons when protected. When not, **Protect…** opens an NSAlert
    naming the file migrate will move ("~/.docker/config.json's registry
    logins move into the vault; the file is backed up encrypted and
    rewritten to use jit's credential helper; docker login/logout keep
    working"), then runs `jit migrate --only docker --yes`, one Touch ID,
    and shows migrate's own output in a result sheet. The wording comes
    from the catalog `Doc`; the file from migrate's plan is not available
    prompt-free, so the alert names the category, not a path, until the
    engine's `jit migrate --dry-run --format json` exists (not asked for
    here).
  - Broken: doctor's own detail sentence and a "Repair" button that re-runs
    `jit wrap <tool>` (catalog) or `jit wrap add <tool> --env …` rebuilt from
    the listing's vars (hand-wrapped).
- **Wrap… sheet.** Says what will happen in the catalog's words before
  anything runs:

  ```
  Wrap gh
  jit will look for the GitHub CLI OAuth token in ~/.config/gh/hosts.yml
  or ask gh for it, move it into the vault at wrap-gh/GH_TOKEN, blank the
  file (backed up encrypted), and put a gh shim first on your PATH.
  Touch ID once. New shells are wrapped; open ones are not until you run
  the PATH line or open a new shell.
                                                    [Cancel]  [Wrap]
  ```

  The sheet's text follows the key state: found in a file (moves and
  blanks it), found in the keychain (copies it, the login stays), or
  nothing found. Only in the last case does it show a SecureField for the
  key, which runs `vault set --stdin` first, then `jit wrap gh`; two
  gestures then, and the sheet says so. The value travels exactly as the
  Vault Add sheet's does. A first version showed the field whenever the
  vault held nothing, with "optional" in the placeholder, and read as a
  demand for a key jit had already found.
- **Unwrap… dialog.** An NSAlert: shim removed, wrap profile removed, the
  vault secret kept ("delete it from the Vault window if you no longer
  need it"). Then `jit wrap undo <tool>`. The PATH line comes out only when
  the shim dir empties; the engine decides and the app repeats its output.
- **Hand-wrap.** A "Wrap Another Tool…" button under the table: tool name,
  VAR, vault path from a `GroupComboBox` of vault paths. Runs `wrap add`.
  Phase 2, and only because the CLI has it; most users never need it.

## 4. Guards, in Settings

```
Shell
  [x] Keep typed credentials out of zsh history
      A command carrying a recognized credential stays usable in that
      session but is never written to the history file. Shells already
      open keep what they loaded until they exit.
```

Toggle on runs `jit guard history`, off runs `--remove`; both refresh
`status`. Not in the Service section: it restarts nothing and needs no
gesture. If `status.guard.installed` disagrees with what the user just set
(the rc line is commented out by hand), the toggle shows the engine's answer
and a note "the line in ~/.zshrc is disabled", because the toggle must never
claim a protection the engine says is off.

## 5. AI agents, the row and what it claims

The AI Agents row is the feature's front door, and it may claim exactly
three things per installed agent, each backed by an engine fact:

1. **Its key is wrapped.** From the tool listing: the agent's catalog
   entry is in the manifest with a healthy shim. Its API key lives in the
   vault and is injected only into that agent's process. Fix: Wrap…, the
   same sheet as any shim tool.
2. **Its caches are clean.** From the last whole-Mac scan: no
   `agent_cached_secret` finding whose agent label is this one. This is
   the fact that surprises people; Claude Code on this Mac kept verbatim
   copies of vaulted credentials in its edit history. Fix: Clean Caches…,
   which is `jit migrate caches`. Phase 1 runs it in the terminal (it
   prints a plan and asks). Phase 3 runs it in-app: a dialog with the
   scan's own counts, then `--yes`, one Touch ID, and the CLI's result
   text in a sheet. The dry-run also decrypts the vault, so there is no
   gesture-free preview. "Not scanned yet" when no whole-Mac scan has run,
   and the fix is Scan Now.
3. **Its reach is gated.** From `status.consent_enabled`: when the agent
   runs `aws`, `git push` or anything else that reaches a machine
   credential through jit, JitPass asks first, naming the agent as the
   launcher. Machine-wide, so it is one line for every agent, with a
   Settings link when off.

The row's dot is the worst of the three across every installed agent. A
fourth claim is not available: the engine cannot see what an agent sends
over the network, and nothing in the row or the bar may read as if it
does. The same three facts appear in the scan window's "AI agent caches"
section (grouped by agent and area, with the Clean Caches… button) and in
the Tools window's selection bar, so the story is the same wherever the
user meets it.

## 6. State and plumbing

- `JitAgentClient` gains `ToolListing` decoded from
  `jit wrap list --all --format json`: `ToolRecord` (tool, kind, doc,
  installedPath, wrapped, addedUnix, shim: ok/missing/broken with detail,
  injects [var, vaultPath, stored], capture, with, runGrant, verifyHint,
  nativeCategory, nativeProtected). Derived: `isAgent` (a fixed set of the
  eight names, the one list the app keeps, because the catalog has no
  "agent" flag and adding one is a bigger engine change than it is worth),
  `state`, `sections`. `CLIStatus` gains `guard.installed` and
  `sessions[]`, which it does not decode today.
- `MenuModel` gains `toolListing`, `toolsBusy: String?`, `toolsMessage`,
  `toolsNotice`, `toolsSheet: ToolsSheet?` (`wrap(tool:)`, `handWrap`,
  `result(title:text:)`), `toolsValue` and `agentsValue` for the two
  panel rows, `agentsDot` computed from the listing, `macScan` and
  `consentEnabled`, and `guardInstalled`.
- `JitCLI.toolList()` follows `vaultList()`. Writes go through `execute`.
  `JitCLI.environment` adds `~/.jit/shims` after Homebrew.
- `StatusItemController+Tools.swift` owns the window, the sheet, and
  `runTools(_:work:then:)`, the same one-at-a-time shape as `runVault`,
  refreshing the listing and `status` after every write. Wrap and unwrap
  also mark the scan stale, since both change coverage.
- `SettingsView` gains the Shell section and `SettingsActions.setGuard`.
- `ScanReportView` gains `agentCacheSection` fed by a new
  `ScanReport.agentCaches: [ScanAgentGroup]` grouped on `findingType ==
  "agent_cached_secret"` by agent label parsed from the evidence's "kept by
  X" tail, or, better, from a new `agent` field the engine can add to the
  finding for free. The evidence parse is the phase-1 fallback.
- The Vault window's detail line uses `expiresUnix` already decoded.

## 7. Rules

1. The app never touches `~/.jit/wrap.json`, `~/.jit/shims`, `~/.jit/guard.zsh`
   or an rc file. Every change is a jit command, and every state word is
   jit's verdict, never the app's own check.
2. `--yes` only after a dialog that names what runs. `migrate caches` in
   phase 1 goes to the terminal because its plan needs the vault open to
   print; native Protect runs in-app because the catalog can name what
   moves without a gesture.
3. A token typed into the Wrap sheet reaches jit through stdin, never argv,
   like the Vault Add sheet.
4. Minting and verifying run in the terminal. Both talk to the user (MFA,
   the tool's own output), and the app must not swallow that.
5. The app never promises consent for a wrapped tool. Wrap is outside the
   consent gate by the engine's decision; the Tools window says what
   consent does cover and leaves it there.
6. Prompt-free on open: `wrap list` and `status` only. Nothing in this
   window triggers Touch ID until a button is pressed.

## 8. Engine changes, in jit, before phase 1

0. Shipped in 1.6.0: items 1 and 2. Added for 1.6.1: **`--discover`** on
   `wrap list --all`, running `wrap.DiscoverToken` for each installed,
   unwrapped shim tool and serializing `key_found` / `key_source` only
   (the value is dropped; a test asserts the fixture token never appears
   in the output); and the **native delegation fix**: `jit wrap aws` ran
   `jit migrate home --only aws`, and migrate read "home" as a relative
   path, so the command failed from every directory without a `home`
   entry. `wrap.Delegation` now takes the home directory and passes it
   absolute. The app passes the absolute path itself either way.
1. **`jit wrap list --format json [--all]`.** The text table's rows plus
   `wrap.Doctor`'s per-tool verdict and the catalog's `Doc`, `VerifyHint`
   and sources, and whether each injected vault path is stored (one
   `Exists` stat each, prompt-free, like `wrapSecretAlreadyVaulted`).
   `--all` appends catalog entries not in the manifest with
   `installed_path` from a PATH lookup that skips the shim dir, so the app
   never guesses what is installed. For native entries, `protected` from
   the migrate index the same way `jit status` knows a category is wired.
   Small: every piece exists in `internal/wrap` and `internal/cli/wrap.go`.
2. **`agent` on `agent_cached_secret` findings.** The scanner has the
   label in hand when it writes the evidence sentence; a field costs one
   line and saves the app a string parse.
3. Nothing else. `guard` install/remove exit codes and `status` are enough;
   `wrap undo` and `migrate caches` keep their text output until phase 3
   wants a result sheet.

## 9. Phases

1. **See.** Engine JSON ships in jit; app pins it. AI Agents and Tools
   rows; the window listing agents, wrapped, native and
   installed-unwrapped tools with state; the three-fact bar per agent;
   sessions under clisso with "Mint in Terminal"; "Verify in Terminal";
   Shell section with the guard toggle; "AI agent caches" heading in the
   scan window with "Clean in Terminal"; expiry in the Vault window; shim
   dir on the app's PATH.
2. **Act.** Wrap sheet (with the store-first field), Unwrap dialog,
   Repair, native Protect dialog with the result sheet, the scan window's
   Protect moved onto the same dialog, hand-wrap sheet.
3. **Clean.** `migrate caches` in-app with a result sheet; notifications
   when a captured session expires or a scan finds new cached copies, if
   the user wants them (the panel values already say it).

## 10. Decisions

Taken 2026-09-17:

- **Two rows, two windows.** "AI Agents" first, "Tools" under it. One
  window was tried and reverted the same day (§2).
- **Panel values are one fact each.** "2 of 2", "3 cached copies",
  "1 expired", "1 to protect", "1 wrapped". The dot carries the rest; the
  windows carry the detail.
- **Skills are not a surface.** The engine scans nothing called a skill,
  so the AI Agents window claims nothing about them.
- **Guard toggle in Settings**, Shell section.
- **Native tools in the window**, with an in-app Protect dialog rather
  than a terminal trip; the scan window's Protect follows in phase 2.
- **The AI-agent name list lives in the app** (`ToolRecord.isAgent`, eight
  names). A catalog `tags` field only if a third surface needs it.
- **Red on cached copies.** Any `agent_cached_secret` finding turns the
  AI Agents dot red. The scanner only hunts values it has already confirmed
  as real credentials and drops test fixtures before it starts, so a copy
  is a live leak by construction, not a maybe. Amber is reserved for an
  installed agent that is unwrapped or consent being off.

Nothing still open.
