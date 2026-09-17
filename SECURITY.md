# Security Policy

JitPass is the menu bar app for jit and talks to jit's background service
over its local socket. It never holds a secret value or a key: the app's op
vocabulary excludes `wrap`, `unwrap` and `reveal_pid`, and a test enforces
that. Even so, if you find a vulnerability, please report it privately, not
as a public GitHub issue.

## Reporting a Vulnerability

Report privately through either channel, please **don't** open a public
issue or PR:

- **Email** the maintainer at **jitpass@outlook.com**, works anytime, no
  GitHub account needed.
- **GitHub private vulnerability reporting**: go to the
  [Security tab](https://github.com/jitpass/jit-app/security) and click
  **"Report a vulnerability"** to open a private advisory thread.

A finding in the service the app talks to belongs in
[jit's security policy](https://github.com/jitpass/jit/blob/main/SECURITY.md);
report it there, or here if you are not sure which side it is on.

Please include, if possible: the affected part (the socket client, a window,
the release pipeline), a minimal reproduction, and which of jit's
[documented boundaries](https://github.com/jitpass/jit/blob/main/docs/security/architecture.md)
you believe is crossed.

## Response Expectations

JitPass is maintained by a single person, part-time. There is no formal SLA,
but security reports get priority over everything else in progress.

## Scope

Everything under `Sources/`, `Resources/`, `scripts/` and `.github/` is in
scope. `docs/design/` holds mockups and the design document, not shipped code.
