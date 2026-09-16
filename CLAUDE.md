# CLAUDE.md

Guidance for Claude Code in this repository. The engine lives in
`jitpass/jit`; read that repo's `CLAUDE.md` and `internal/agent/protocol.go`
before touching anything that speaks to the socket.

## Commands

```sh
swift build
swift test
swift run JitPass
scripts/bundle.sh release          # dist/JitPass.app
swiftformat --lint . && swiftlint --strict
```

CI (`.github/workflows/ci.yml`) is the canonical gate: format, lint, SPDX
headers, build, test, bundle. Xcode is not required; the project is a plain
Swift Package with no `.xcodeproj` checked in (and `.gitignore` refuses one).

## Architecture rules

- **`JitAgentClient` has no AppKit import and `JitPassApp` has no socket
  code.** The library is what tests cover; the app is rendering plus one
  method call per menu item.
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

## Conventions

- Every `.swift` file carries the SPDX header (CI fails without it).
- Swift 5 language mode for now; `@MainActor` on anything touching AppKit.
- Commit dates: same rule as jit, nothing Sun-Thu 09:00-18:00 Asia/Jerusalem.
- Push as `menitasa`, never `menit-sec`, with the gh credential helper
  override from jit's memory notes.
