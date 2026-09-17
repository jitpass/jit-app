# Contributing to JitPass

Thanks for your interest in JitPass, the menu bar app for
[jit](https://github.com/jitpass/jit). The app is a thin client of jit's
background service, and the rules below are jit's, applied here.

## Ground rules

- **Sign off your commits (DCO).** Every commit must carry a
  `Signed-off-by:` line certifying the [Developer Certificate of
  Origin](https://developercertificate.org/). Add it with `git commit -s`.

- **Agree to the CLA.** Contributions are covered by the project's
  [Contributor License Agreement](./CLA.md), the same one jit uses: you keep
  copyright in your work and grant the maintainer a broad license including
  the right to relicense your contribution. You accept it by signing off
  your commits and submitting your contribution.

- **License.** JitPass is licensed under the PolyForm Perimeter License
  1.0.0, the same source-available license as jit (see
  [LICENSE](./LICENSE)). All contributions are made under those terms and the
  CLA. Don't paste in code under an incompatible license.

- **Security issues are not regular PRs.** See [SECURITY.md](./SECURITY.md).

## Before you start

- Read [docs/design/menu-bar-app.md](./docs/design/menu-bar-app.md): what the
  app shows, which socket op each row is, and the rules the app never breaks.
  The two that matter most: **the app decides nothing** (every prompt is the
  service's own Touch ID; the app only explains or refuses), and **the app
  never speaks `wrap`, `unwrap` or `reveal_pid`**, so no secret or key can
  reach it. A test enforces the second; a review enforces the first.
- Every menu action must be one op the CLI can also send. A feature that
  needs something the CLI cannot do goes into jit first.
- Read [CLAUDE.md](./CLAUDE.md) for the build gate and the architecture
  rules; they apply to humans too.

## Development

Requires macOS 14+, Xcode (for `swift test` and SwiftLint), and jit
installed for anything beyond the unit tests.

```sh
scripts/gate.sh          # format, lint, build, test: what CI runs
scripts/gate.sh --run    # same, then bundle and relaunch the dev build
```

The tests never touch a real service: they drive the real client against a
fake agent on a temporary socket.

## Pull requests

- Keep PRs focused; one logical change per PR.
- Anything user-visible gets a screenshot in the PR.
- Make sure `git commit -s` sign-off is present on every commit (this also
  signals your acceptance of the [CLA](./CLA.md)).
