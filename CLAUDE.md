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
  `unwrap` or `reveal_pid`.** `testAppNeverSpeaksWrapOrUnwrap` enforces it.
  That is the whole guarantee that no plaintext or data key reaches this
  process; do not widen it for convenience.
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

## Release rules

Same as jit's: never ship unsigned (the workflow's preflight refuses rather
than skipping), sign by TEAM ID never by identity name (this machine's
keychain holds a second, unrelated team), verify the PUBLISHED zip and not
`dist/`, publish as a draft and undraft only after that verification. The
bundle CAN be stapled, unlike jit's bare binary, so the cask needs no online
ticket fetch. Local credentials live in `~/.apple-signing`; the five Apple
secrets are set on this repo; `HOMEBREW_TAP_GITHUB_TOKEN` is not, so the
cask is pushed to the tap by hand until it is.

## Conventions

- Every `.swift` file carries the SPDX header (CI fails without it).
- Swift 5 language mode for now; `@MainActor` on anything touching AppKit.
- Commit dates: same rule as jit, nothing Sun-Thu 09:00-18:00 Asia/Jerusalem.
- Push as `menitasa`, never `menit-sec`, with the gh credential helper
  override from jit's memory notes.
