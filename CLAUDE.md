# CLAUDE.md

Guidance for Claude Code in this repository. The engine lives in
`jitpass/jit`; read that repo's `CLAUDE.md` and `internal/agent/protocol.go`
before touching anything that speaks to the socket.

## Commands

```sh
scripts/gate.sh                    # format, lint, build, test: the ONLY way to build for a commit
scripts/gate.sh --run              # same, then bundle and relaunch the dev build
swift run JitPass
```

Never chain the build through `grep` or `;` by hand: that swallowed a
compile error twice and pushed commits that did not build. `gate.sh` fails
on the first failing step.

CI (`.github/workflows/ci.yml`) is the canonical gate: format, lint, SPDX
headers, build, test, bundle. Run `swiftformat .` before `--lint`; the
formatter's own defaults are the style, the config only sets width and the
header. The project is a plain Swift Package with no `.xcodeproj` checked in
(and `.gitignore` refuses one). `swift build` works with the command line
tools alone, but `swift test` and `swiftlint` need Xcode's toolchain: if
`xcode-select -p` still points at the CLT, prefix commands with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Architecture rules

- **`JitAgentClient` has no AppKit import and `JitPassApp` has no socket
  code.** The library is what tests cover; the app is rendering plus one
  method call per menu item. Inside the library, `UnixSocket` holds every
  POSIX call and `AgentClient` holds only protocol logic; the test fake
  (`FakeAgent`) is built on the same `UnixSocket` helpers so the framing
  cannot drift between the two.
- **User-facing strings are composed in `Format`, never inline in menu
  building.** One place to change wording, and the controller stays a list
  of rows.
- **The app's op vocabulary is `AgentOp`, and it never contains `wrap`,
  `unwrap`, `reveal_pid` or `job_run`.** `testAppNeverSpeaksWrapOrUnwrap`
  enforces it. That is the whole guarantee that no plaintext or data key
  reaches this process; do not widen it for convenience. AI Jobs are
  approved, listed, removed and previewed here, never run: running one is
  what an AI tool does, through `jit job run` or `jit mcp`.
- **Every menu action must be one op the CLI can also send.** If a feature
  needs something the CLI cannot do, add the op to the agent and the CLI
  first (in `jitpass/jit`), then use it here. The app is never the only way
  to do something.
- **Mirror the protocol, never fork it.** Field names and ops are copied
  from `internal/agent/protocol.go` with snake_case coding keys. New fields
  are optional on decode so an older agent still renders.
- **No decisions in the app.** Unlock triggers the agent's own challenge;
  revoke is unauthenticated by design; consent brokering (phase 4) parks the
  agent's request and returns the human's answer, nothing more.
- **Colour carries state, in jit's palette.** Green unlocked, red locked or
  not running, amber a question. Values live in `StatusMark` only.
- **Dependencies: none.** Foundation and AppKit. Adding a package needs the
  same justification jit's `TECH_STACK.md` §2 demands.

## Design rules

- **The design system is the source, not this repo.** Every window is
  built from the JitPass design system, section **Windows**:
  <https://claude.ai/artifact/AD9fUEBsrojwJMLyeTarY7>. Read that section
  before you build or redesign any window, sheet or alert. It has the
  regions, the three-width ladder, the six-step spacing scale, the type
  scale, every control, the outcome states and the rules for a question.
- **`DesignSystem.swift` is that section in Swift.** Use `Design.Space`,
  `Design.Text`, `Design.Radius`, `Design.Window`, `Design.Size`, `Design.Surface` and
  `Design.Label` instead of a literal. A number that is not in `Design` is missing
  from the system: add it to the artifact's `tokens.json` and `windows.md`
  first, then to `Design`, and never pick one in the view.
- **One rule diverges from the published system, on purpose (2026-09-23).**
  Windows still says the row's "new" chip is `app-label-2` on `app-field`,
  "never a colour", and says nothing about row order. The app ships the
  chip's WORD in `app-action` on that same neutral fill, and sorts rows
  carrying one to the top of their card. Do not "fix" it back by reading
  that page: the grey word measures 3.72:1 on a card, under the 4.5:1
  floor the same page requires, and the coloured word on the neutral fill
  measures 4.91:1. A tinted fill was drawn, measured at 4.33:1 and
  dropped. Meni decided not to republish the artifact, so the divergence
  is deliberate and lives here.
- **State colour stays in `StatusMark`.** `Design` deliberately holds none, so
  the menu bar mark, the panel dots and a window's rows cannot disagree
  about what green means. Every state dot is 8pt and always sits beside a
  word: red at that size on the window material is 2.3:1.
- **No terminal pane reports success.** A command's output is not an
  answer. While it runs, the row spins; when it works, the row says so in
  the past tense, or the window's banner does; when it fails, the row
  carries a sentence saying what to do and jit's own words verbatim under
  it. `DoctorDialogs.showOutput` keeps only its failure role.
- **The terminal is not banned, it is not a substitute.** Three cases, and
  only the first two are ruled out: a terminal pane inside the app for a
  success (never); the terminal standing in for a window the app has or
  should have, such as a footer re-running `jit doctor` (remove); and a
  genuinely interactive session such as a tool log-in, which opens a
  browser and waits at a prompt (hand it to `Terminal.run`, label it
  "… opens your terminal", and keep its command line, because the app is
  not running it). The test: could the app do this itself? One known
  exception is carried on purpose, `AuditView.capNote`'s "Open in Terminal
  for the rest", which waits on the engine being able to page an audit
  log.
- **A question names the thing, it does not quote the command.** Two
  exceptions keep their command: when the flag *is* the decision
  (`--break-profiles`), and when the app is about to put that line in the
  user's terminal rather than run it. "Touch ID follows" stays; "Nothing
  asks again" goes, because it is true of all of them. Escape cancels,
  Return never destroys.
- **Surfaces are overlays, not fills.** Windows draw a translucent
  material, so `Design.Surface` is white at an alpha. The hex values in the
  artifact's `tokens.json` are samples for static mockups; painting them
  would stop the window tinting with the wallpaper.

## Release rules

Same as jit's: never ship unsigned (the workflow's preflight refuses rather
than skipping), sign by TEAM ID never by identity name (this machine's
keychain holds a second, unrelated team), verify the PUBLISHED zip and not
`dist/`, publish as a draft and undraft only after that verification. The
bundle CAN be stapled, unlike jit's bare binary, so the cask needs no online
ticket fetch. Local credentials live in `~/.apple-signing`; the five Apple
secrets are set on this repo, and so is `HOMEBREW_TAP_GITHUB_TOKEN` (since
2026-09-17), so the cask is pushed to the tap automatically — only after the
release is verified and visible, never at a draft. The workflow still falls
back to printing the cask for a manual push if that token ever goes missing.

## The bundled jit

`jit.version` pins the jit release inside the bundle. `scripts/fetch-jit.sh`
downloads that tag's tarball from github.com, checks it against the
release's own `checksums.txt`, verifies the binary's Developer ID team and
hardened runtime, and stages it under `dist/`; `bundle.sh` copies it to
`Contents/Helpers/JitPassAgent.app/Contents/MacOS/jit`, the main executable
of jit's own helper bundle (`com.jitpass.agent`), leaves `Contents/MacOS/jit`
as a symlink to it for installs made before, and puts the completions under
`Resources/`. `sign.sh` signs the helper first, then the app; never `--deep`. The `jitpass`
cask (`scripts/cask.sh`) installs the app and symlinks that jit onto PATH.
One product, one number: an app tag is the bundled jit's version, plus a
fourth part for an app-only release (`v1.5.8` ships jit 1.5.8, `v1.5.8.1`
is the same jit with an app fix), and `release.yml` refuses a tag that does
not start with `jit.version`. Bumping jit is: edit `jit.version`, run the
gate, commit, tag `v<jit>`. An app-only fix is tagged `v<jit>.N`. jit's own
release never writes the cask. Tags v0.9.x predate this; the cask carried
`<jit>,<app>` until 1.5.8,0.9.3.

## Icon

`Resources/AppIcon.icns` is generated, never hand-edited: `swift
scripts/icon.swift <dir>` draws the jitpass mark (dot in a soft ring, from
jitpass.com/icon.svg) on the macOS plate at every iconset size, and
`iconutil -c icns` compiles it. Regenerate and commit the icns when the mark
changes; the menu bar item draws the same mark in `StatusMark`.

## Conventions

- Every `.swift` file carries the SPDX header (CI fails without it).
- Swift 5 language mode for now; `@MainActor` on anything touching AppKit.
- Commit dates: same rule as jit, nothing Sun-Thu 09:00-18:00 Asia/Jerusalem.
- Push as `menitasa`, never `menit-sec`, with the gh credential helper
  override from jit's memory notes.
