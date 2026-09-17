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

## Install

```sh
brew install jitpass/tap/jit-app     # temporary cask; depends on the jitpass CLI cask
```

## Release

Push a tag `vX.Y.Z`. The workflow builds, Developer ID signs, notarizes and
staples the bundle, publishes a draft, verifies the published zip the way a
user's Mac will, undrafts, and renders the cask. The same steps run locally:

```sh
VERSION=0.1.0 scripts/bundle.sh release
scripts/sign.sh                      # Developer ID identity for team CZC6BH93GJ
NOTARY_KEY_FILE=... NOTARY_KEY_ID=... NOTARY_ISSUER_ID=... scripts/notarize.sh
scripts/verify.sh dist/JitPass-0.1.0-arm64.zip dist/checksums.txt
```

## Layout

```
Sources/JitAgentClient   socket client and protocol models, no AppKit, tested
Sources/JitPassApp       AppKit menu bar app, a view over JitAgentClient
Tests/JitAgentClientTests
Resources/               Info.plist, entitlements
scripts/                 bundle, sign, notarize, verify, cask
docs/design/             design doc and mockup sources
```

## License

[PolyForm Perimeter License 1.0.0](./LICENSE), the same source-available
license as jit: free for personal and internal use; it does not permit
building a competing product on it. Contributions are made under the
[CLA](./CLA.md); see [CONTRIBUTING.md](./CONTRIBUTING.md).
