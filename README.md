# JitPass

The macOS menu bar app for [jit](https://github.com/jitpass/jit), the
just-in-time secrets tool. A lock in the menu bar, the active grants, the
last few audit events, and the prompts that explain themselves.

**Status: released.** Install it below; every version is on the
[releases page](https://github.com/jitpass/jit-app/releases). The design is in
`docs/design/menu-bar-app.md`.

## What it is

- A thin client of the `jit-agent` Unix socket. Every menu action is one
  socket op the `jit` CLI can also send. The app never decides anything on
  its own and never sees a secret value or a data key.
- The place to approve and review AI Jobs (commands an AI tool may run by
  name, getting the output with every secret value hidden) and to connect
  Claude Desktop and Cursor to them. The app approves jobs; it never runs
  one.
- Not mandatory. The CLI keeps working without it, headless and in CI.
- The `.app` bundle jit's Secure Enclave key binding needs (phase 3).

## Build

Requires macOS 14+, Swift 5.10+ and full Xcode: `swift test` needs XCTest,
which the command line tools alone do not ship. `scripts/gate.sh` points
`DEVELOPER_DIR` at `/Applications/Xcode.app` for you. It also runs
`swiftformat` and `swiftlint`, so install both (`brew install swiftformat
swiftlint`).

```sh
scripts/gate.sh            # format, lint, build, test: the same steps CI runs
scripts/gate.sh --run      # and bundle and relaunch the dev build
swift run JitPass          # menu bar item appears; no Dock icon
scripts/bundle.sh release  # dist/JitPass.app, unsigned
```

Build through `scripts/gate.sh` rather than chaining the steps by hand: it
fails on the first step that fails, which a hand-built pipeline once did not.

## Install

```sh
brew install jitpass/tap/jitpass
```

One cask installs JitPass.app into /Applications with the `jit` CLI inside
it, symlinked onto PATH, plus shell completions. The bundled jit is the
release pinned in `jit.version`, fetched and verified at build time. The
older `jit-app` cask is retired; `brew uninstall --cask jit-app` before
installing this one.

Without Homebrew, download the notarized app and drag it into Applications:

```
https://dl.jitpass.com/jitpass/jit-app/releases/latest/download/JitPass-arm64.zip
```

On first launch the app offers to link `jit` into your PATH (Homebrew's bin
without a password, `/usr/local/bin` with one), and it checks GitHub once a
day for a newer release; both live under Settings › General. A copy opened
straight from the download runs from a temporary location, and the app says
so and asks to be moved first.

## Release

The version is the bundled jit's: tag `v<jit.version>` (today `v1.7.0`), or
`v<jit.version>.N` for a release that changes only the app (`v1.7.0.1`). The
workflow refuses a tag that disagrees with `jit.version`.

Push the tag. The workflow builds, Developer ID signs, notarizes and
staples the bundle, publishes a draft, verifies the published zip the way a
user's Mac will, undrafts, and renders the cask. The same steps run locally:

```sh
VERSION=1.7.0 scripts/bundle.sh release   # fetches and verifies the jit in jit.version first
scripts/sign.sh                      # Developer ID identity for team CZC6BH93GJ
NOTARY_KEY_FILE=... NOTARY_KEY_ID=... NOTARY_ISSUER_ID=... scripts/notarize.sh
scripts/verify.sh dist/JitPass-1.7.0-arm64.zip dist/checksums.txt
```

## Layout

```
Sources/JitAgentClient   socket client and protocol models, no AppKit, tested
Sources/JitPassApp       AppKit menu bar app, a view over JitAgentClient
Tests/JitAgentClientTests
Resources/               Info.plist, Agent-Info.plist (jit's helper bundle), entitlements
scripts/                 bundle, sign, notarize, verify, cask
docs/design/             design doc and mockup sources
```

## License

[PolyForm Perimeter License 1.0.0](./LICENSE), the same source-available
license as jit: free for personal and internal use; it does not permit
building a competing product on it. Contributions are made under the
[CLA](./CLA.md); see [CONTRIBUTING.md](./CONTRIBUTING.md).
