# JitPass

The macOS menu bar app for [jit](https://github.com/jitpass/jit), the
just-in-time secrets tool. A lock in the menu bar, the active grants, the
last few audit events, and the prompts that explain themselves.

**Status: phase 1, unreleased.** See `docs/design/menu-bar-app.md` for the
plan and `docs/design/mockups/` for what it will look like.

## What it is

- A thin client of the `jit-agent` Unix socket. Every menu action is one
  socket op the `jit` CLI can also send. The app never decides anything on
  its own and never sees a secret value or a data key.
- Not mandatory. The CLI keeps working without it, headless and in CI.
- The `.app` bundle jit's Secure Enclave key binding needs (phase 3).

## Build

Requires macOS 14+ and Swift 5.10+ (Xcode command line tools are enough).

```sh
swift build
swift test
swift run JitPass          # menu bar item appears; no Dock icon
scripts/bundle.sh release  # dist/JitPass.app, unsigned
```

## Layout

```
Sources/JitAgentClient   socket client and protocol models, no AppKit, tested
Sources/JitPassApp       AppKit menu bar app, a view over JitAgentClient
Tests/JitAgentClientTests
Resources/               Info.plist, entitlements
scripts/                 bundle.sh
docs/design/             design doc and mockup sources
```

## License

PolyForm Perimeter 1.0.0, the same as jit. See `LICENSE`.
