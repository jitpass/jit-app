// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

/// `jit doctor --format json` from jit 2.1.0 (jitpass/jit doctor-ignore,
/// 75cbc25) in a throwaway home, renamed to /Users/me: three AWS profiles
/// (dev and admin clisso apps nobody has logged into, qa not one), a profile
/// missing two secrets whose record names a deleted config, and clisso's
/// wrap. aws-dev and aws-admin were ignored; then [profile dev] gained a
/// region, so aws-dev is back with ignore_changed and aws-admin stays in
/// "ignored".
enum DoctorIgnoreFixture {
    static let json = #"""
    {"schema_version":2,"tool":{"version":"2.1.0","build":"75cbc2508abf","signature":"signed CZC6BH93GJ"},
    "profiles_checked":1,"secrets_checked":2,"ok":false,"problems":[{"kind":"missing","profile":"mcp-okta-mcp-server",
    "scope":"global","variable":"OKTA_ORG_URL","path":"mcp-okta-mcp-server/OKTA_ORG_URL","detail":"","action":
    "`jit vault set mcp-okta-mcp-server/OKTA_ORG_URL`, or `jit migrate <path>` to convert the file it came from",
    "fixes":[{"command":"jit vault set mcp-okta-mcp-server/OKTA_ORG_URL","argv":["vault","set",
    "mcp-okta-mcp-server/OKTA_ORG_URL"],"destructive":false,"presence":true},{"command":"jit migrate <path>",
    "argv":["migrate","<path>"],"destructive":false,"presence":false,"needs":"<path>"}],"launchers":[{"kind":"mcp","file":
    "/Users/me/Security-Ops/.mcp.json","detail":"okta-mcp-server","profile":"mcp-okta-mcp-server"}],"ignore":{"kind":
    "missing","name":"mcp-okta-mcp-server","argv":["jit","doctor","ignore","--kind","missing","mcp-okta-mcp-server"]}},
    {"kind":"missing","profile":"mcp-okta-mcp-server","scope":"global","variable":"OKTA_SCOPES","path":
    "mcp-okta-mcp-server/OKTA_SCOPES","detail":"","action":
    "`jit vault set mcp-okta-mcp-server/OKTA_SCOPES`, or `jit migrate <path>` to convert the file it came from",
    "fixes":[{"command":"jit vault set mcp-okta-mcp-server/OKTA_SCOPES","argv":["vault","set",
    "mcp-okta-mcp-server/OKTA_SCOPES"],"destructive":false,"presence":true},{"command":"jit migrate <path>",
    "argv":["migrate","<path>"],"destructive":false,"presence":false,"needs":"<path>"}],"launchers":[{"kind":"mcp","file":
    "/Users/me/Security-Ops/.mcp.json","detail":"okta-mcp-server","profile":"mcp-okta-mcp-server"}],"ignore":{"kind":
    "missing","name":"mcp-okta-mcp-server","argv":["jit","doctor","ignore","--kind","missing","mcp-okta-mcp-server"]}},
    {"kind":"profile_missing","profile":"aws-qa","detail":
    "~/.aws/config [profile qa] names profile aws-qa, which no jit store holds","action":
    "no such jit profile, so aws --profile qa fails; mint it again, or delete that [profile] block","file":
    "/Users/me/.aws/config","launchers":[{"kind":"aws","file":"/Users/me/.aws/config","detail":"[profile qa]","profile":
    "aws-qa"}],"ignore":{"kind":"profile_missing","name":"aws-qa","argv":["jit","doctor","ignore","--kind",
    "profile_missing","aws-qa"]}}],"warnings":[{"kind":"not_logged_in","profile":"aws-dev","detail":
    "~/.aws/config [profile dev] names profile aws-dev, which clisso makes the first time you log in","action":
    "`clisso get dev`","fixes":[{"command":"clisso get dev","argv":["clisso","get","dev"],"external":true,
    "destructive":false,"presence":true}],"file":"/Users/me/.aws/config","launchers":[{"kind":"aws","file":
    "/Users/me/.aws/config","detail":"[profile dev]","profile":"aws-dev"}],"ignore":{"kind":"not_logged_in","name":
    "aws-dev","argv":["jit","doctor","ignore","--kind","not_logged_in","aws-dev"]},"ignore_changed":true},{"kind":
    "config_deleted","profile":"mcp-okta-mcp-server","scope":"global","path":
    "/Users/me/.jit/profiles/mcp-okta-mcp-server.yaml","detail":
    "recorded config ~/Documents/ai_security_workspace/.mcp.json is deleted; now started by ~/Security-Ops/.mcp.json",
    "action":"`jit profile attach ~/Security-Ops/.mcp.json`","fixes":[{"command":
    "jit profile attach ~/Security-Ops/.mcp.json","argv":["profile","attach","/Users/me/Security-Ops/.mcp.json"],
    "destructive":false,"presence":false}],"config":"/Users/me/Security-Ops/.mcp.json",
    "configs":["/Users/me/Security-Ops/.mcp.json"],"owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],
    "launchers":[{"kind":"mcp","file":"/Users/me/Security-Ops/.mcp.json","detail":"okta-mcp-server","profile":
    "mcp-okta-mcp-server"}],"ignore":{"kind":"config_deleted","name":"mcp-okta-mcp-server","argv":["jit","doctor",
    "ignore","--kind","config_deleted","mcp-okta-mcp-server"]}},{"kind":"wrap_env","detail":
    "PATH: shim dir not on PATH in this shell, open a new shell or `export PATH=\"$HOME/.jit/shims:$PATH\"`",
    "ignore":{"kind":"wrap_env","name":"PATH","argv":["jit","doctor","ignore","--kind","wrap_env","PATH"]}},{"kind":
    "wrap_env","detail":"tool clisso: real clisso not found on PATH beyond the shim dir, is it still installed?",
    "ignore":{"kind":"wrap_env","name":"tool clisso","argv":["jit","doctor","ignore","--kind","wrap_env",
    "tool clisso"]}}],"ignored":[{"kind":"not_logged_in","profile":"aws-admin","detail":
    "~/.aws/config [profile admin] names profile aws-admin, which clisso makes the first time you log in","action":
    "`clisso get admin`","fixes":[{"command":"clisso get admin","argv":["clisso","get","admin"],"external":true,
    "destructive":false,"presence":true}],"file":"/Users/me/.aws/config","launchers":[{"kind":"aws","file":
    "/Users/me/.aws/config","detail":"[profile admin]","profile":"aws-admin"}],"ignore":{"kind":"not_logged_in","name":
    "aws-admin","argv":["jit","doctor","ignore","--kind","not_logged_in","aws-admin"]},"ignored_since":"2026-09-19",
    "severity":"warning","unignore":{"argv":["jit","doctor","unignore","--kind","not_logged_in","aws-admin"]}}]}
    """#

    /// `jit doctor ignore --kind not_logged_in aws-dev --format json`, then
    /// `jit doctor unignore --kind not_logged_in aws-admin --format json`.
    static let ignored = #"{"ignored":[{"kind":"not_logged_in","name":"aws-dev"}],"unignored":[]}"#
    static let unignored = #"{"ignored":[],"unignored":[{"kind":"not_logged_in","name":"aws-admin"}]}"#
}
