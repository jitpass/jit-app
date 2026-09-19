// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

/// A whole `jit doctor --format json` of the released jit 2.0.0 on a real
/// Mac, home renamed to /Users/me and one company name to acme: the
/// problems, the backup and old-format warnings and the three nested MCP
/// wrappers as captured, and before them the seven record findings and
/// after them the two no-known-tool ones from the same Mac before its
/// profiles were attached (four and both in jit 2.0.0's own words from
/// DoctorOwnershipTests' capture; mcp-google-workspace-investigate,
/// mcp-jamf and mcp-okta-mcp-server from the pre-release capture of that
/// morning, put in the same 2.0.0 shape).
enum DoctorBoardFixture {
    static let json = #"""
    {"schema_version":2,"tool":{"version":"2.0.0","build":"379d970e2818","signature":"signed CZC6BH93GJ"},"profiles_checked":22,
    "secrets_checked":68,"ok":false,"problems":[{"kind":"missing","profile":"mcp-google-workspace-investigate","scope":"global",
    "variable":"GOOGLE_CLOUD_PROJECT","path":"mcp-google-workspace-investigate/GOOGLE_CLOUD_PROJECT","detail":"","action":
    "`jit vault set mcp-google-workspace-investigate/GOOGLE_CLOUD_PROJECT`, or `jit migrate <path>` to convert the\#
     file it came from",
    "fixes":[{"command":"jit vault set mcp-google-workspace-investigate/GOOGLE_CLOUD_PROJECT","argv":["vault","set",
    "mcp-google-workspace-investigate/GOOGLE_CLOUD_PROJECT"],"destructive":false,"presence":true},{"command":
    "jit migrate <path>","argv":["migrate","<path>"],"destructive":false,"presence":false,"needs":"<path>"}]},{"kind":"missing",
    "profile":"mcp-okta-mcp-server","scope":"global","variable":"OKTA_ORG_URL","path":"mcp-okta-mcp-server/OKTA_ORG_URL",
    "detail":"","action":
    "`jit vault set mcp-okta-mcp-server/OKTA_ORG_URL`, or `jit migrate <path>` to convert the file it came from",
    "fixes":[{"command":"jit vault set mcp-okta-mcp-server/OKTA_ORG_URL","argv":["vault","set",
    "mcp-okta-mcp-server/OKTA_ORG_URL"],"destructive":false,"presence":true},{"command":"jit migrate <path>","argv":["migrate",
    "<path>"],"destructive":false,"presence":false,"needs":"<path>"}]},{"kind":"missing","profile":"mcp-okta-mcp-server",
    "scope":"global","variable":"OKTA_SCOPES","path":"mcp-okta-mcp-server/OKTA_SCOPES","detail":"","action":
    "`jit vault set mcp-okta-mcp-server/OKTA_SCOPES`, or `jit migrate <path>` to convert the file it came from",
    "fixes":[{"command":"jit vault set mcp-okta-mcp-server/OKTA_SCOPES","argv":["vault","set",
    "mcp-okta-mcp-server/OKTA_SCOPES"],"destructive":false,"presence":true},{"command":"jit migrate <path>","argv":["migrate",
    "<path>"],"destructive":false,"presence":false,"needs":"<path>"}]},{"kind":"profile_missing","profile":"aws-dev","detail":
    "~/.aws/config [profile dev] names profile aws-dev, which no jit store holds","action":
    "no such jit profile, so aws --profile dev fails; mint it again, or delete that [profile] block","file":
    "/Users/me/.aws/config","launchers":[{"kind":"aws","file":"/Users/me/.aws/config","detail":"[profile dev]","profile":
    "aws-dev"}]},{"kind":"profile_missing","profile":"aws-admin","detail":
    "~/.aws/config [profile admin] names profile aws-admin, which no jit store holds","action":
    "no such jit profile, so aws --profile admin fails; mint it again, or delete that [profile] block","file":
    "/Users/me/.aws/config","launchers":[{"kind":"aws","file":"/Users/me/.aws/config","detail":"[profile admin]","profile":
    "aws-admin"}]},{"kind":"pointer_missing","path":"jitpass-playground-bak/API_KEY","detail":
    "~/Documents/jitpass-playground/.env.bak points at jitpass-playground-bak/API_KEY, which isn't in the vault","action":
    "`jit vault set jitpass-playground-bak/API_KEY`","fixes":[{"command":"jit vault set jitpass-playground-bak/API_KEY",
    "argv":["vault","set","jitpass-playground-bak/API_KEY"],"destructive":false,"presence":true}],"file":
    "/Users/me/Documents/jitpass-playground/.env.bak"},{"kind":"pointer_missing","path":"wrap-clisso/acme-client-secret",
    "detail":"~/.clisso.yaml points at wrap-clisso/acme-client-secret, which isn't in the vault","action":
    "`jit vault set wrap-clisso/acme-client-secret`","fixes":[{"command":"jit vault set wrap-clisso/acme-client-secret",
    "argv":["vault","set","wrap-clisso/acme-client-secret"],"destructive":false,"presence":true}],"file":
    "/Users/me/.clisso.yaml"}],"warnings":[{"kind":"config_deleted","profile":"mcp-caido","scope":"global","path":
    "/Users/me/.jit/profiles/mcp-caido.yaml","detail":
    "recorded config ~/Documents/ai_security_workspace/.mcp.json is deleted; now started by ~/Security-Ops/.mcp.json","action":
    "`jit profile attach ~/Security-Ops/.mcp.json`","fixes":[{"command":"jit profile attach ~/Security-Ops/.mcp.json",
    "argv":["profile","attach","/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],"config":
    "/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"launchers":[{"kind":"mcp","file":
    "/Users/me/Security-Ops/.mcp.json","detail":"caido","profile":"mcp-caido"},{"kind":"mcp","file":
    "/Users/me/Security-Ops/.mcp.json","detail":"caido","profile":"mcp-caido","layer":1}]},{"kind":"config_deleted","profile":
    "mcp-google-workspace-investigate","scope":"global","path":"/Users/me/.jit/profiles/mcp-google-workspace-investigate.yaml",
    "detail":"recorded config ~/Documents/ai_security_workspace/.mcp.json is deleted; now started by ~/Security-Ops/.mcp.json",
    "action":"`jit profile attach ~/Security-Ops/.mcp.json`","fixes":[{"command":"jit profile attach ~/Security-Ops/.mcp.json",
    "argv":["profile","attach","/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],"config":
    "/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"launchers":[{"kind":"mcp","file":
    "/Users/me/Security-Ops/.mcp.json","detail":"google-workspace-investigate","profile":"mcp-google-workspace-investigate"}]},
    {"kind":"config_deleted","profile":"mcp-jamf","scope":"global","path":"/Users/me/.jit/profiles/mcp-jamf.yaml","detail":
    "recorded config ~/Documents/ai_security_workspace/.mcp.json is deleted; now started by ~/Security-Ops/.mcp.json","action":
    "`jit profile attach ~/Security-Ops/.mcp.json`","fixes":[{"command":"jit profile attach ~/Security-Ops/.mcp.json",
    "argv":["profile","attach","/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],"config":
    "/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"launchers":[{"kind":"mcp","file":
    "/Users/me/Security-Ops/.mcp.json","detail":"jamf","profile":"mcp-jamf"}]},{"kind":"config_deleted","profile":"mcp-okta",
    "scope":"global","path":"/Users/me/.jit/profiles/mcp-okta.yaml","detail":
    "recorded config ~/Documents/ai_security_workspace/.mcp.json is deleted; now started by ~/Security-Ops/.mcp.json","action":
    "`jit profile attach ~/Security-Ops/.mcp.json`","fixes":[{"command":"jit profile attach ~/Security-Ops/.mcp.json",
    "argv":["profile","attach","/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],"config":
    "/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"launchers":[{"kind":"mcp","file":
    "/Users/me/Security-Ops/.mcp.json","detail":"okta-mcp-server","profile":"mcp-okta","layer":1}]},{"kind":"config_deleted",
    "profile":"mcp-okta-mcp-server","scope":"global","path":"/Users/me/.jit/profiles/mcp-okta-mcp-server.yaml","detail":
    "recorded config ~/Documents/ai_security_workspace/.mcp.json is deleted; now started by ~/Security-Ops/.mcp.json","action":
    "`jit profile attach ~/Security-Ops/.mcp.json`","fixes":[{"command":"jit profile attach ~/Security-Ops/.mcp.json",
    "argv":["profile","attach","/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],"config":
    "/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],
    "owners":["/Users/me/Documents/ai_security_workspace/.mcp.json"],"launchers":[{"kind":"mcp","file":
    "/Users/me/Security-Ops/.mcp.json","detail":"okta-mcp-server","profile":"mcp-okta-mcp-server"}]},{"kind":
    "config_not_recorded","profile":"mcp-google-workspace","scope":"global","path":
    "/Users/me/.jit/profiles/mcp-google-workspace.yaml","detail":"no config recorded; started by ~/Security-Ops/.mcp.json",
    "action":"`jit profile attach ~/Security-Ops/.mcp.json`","fixes":[{"command":"jit profile attach ~/Security-Ops/.mcp.json",
    "argv":["profile","attach","/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],"config":
    "/Users/me/Security-Ops/.mcp.json","configs":["/Users/me/Security-Ops/.mcp.json"],"launchers":[{"kind":"mcp","file":
    "/Users/me/Security-Ops/.mcp.json","detail":"google-workspace-investigate","profile":"mcp-google-workspace","layer":1}]},
    {"kind":"config_not_recorded","profile":"mcp-urlscan","scope":"global","path":"/Users/me/.jit/profiles/mcp-urlscan.yaml",
    "detail":"no config recorded; started by ~/Security-Ops/.mcp.json","action":"`jit profile attach ~/Security-Ops/.mcp.json`",
    "fixes":[{"command":"jit profile attach ~/Security-Ops/.mcp.json","argv":["profile","attach",
    "/Users/me/Security-Ops/.mcp.json"],"destructive":false,"presence":false}],"config":"/Users/me/Security-Ops/.mcp.json",
    "configs":["/Users/me/Security-Ops/.mcp.json"],"launchers":[{"kind":"mcp","file":"/Users/me/Security-Ops/.mcp.json",
    "detail":"urlscan","profile":"mcp-urlscan"}]},{"kind":"legacy_envelope","detail":
    "11 secrets use an old format that cannot tell if a value was swapped on disk.","action":
    "`jit vault export <file>` then `jit vault import <file>` re-encrypts every secret in the current format (the\#
     export doubles as the backup below)",
    "fixes":[{"command":"jit vault export <file>","argv":["vault","export","<file>"],"destructive":false,"presence":true,
    "needs":"<file>"},{"command":"jit vault import <file>","argv":["vault","import","<file>"],"destructive":true,
    "presence":true,"needs":"<file>"}]},{"kind":"backup","detail":
    "no vault export on record, so the vault only decrypts on this Mac.","action":
    "`jit vault export <file>` makes a copy you could restore on another Mac","fixes":[{"command":"jit vault export <file>",
    "argv":["vault","export","<file>"],"destructive":false,"presence":true,"needs":"<file>"}]},{"kind":"mcp_nested","profile":
    "mcp-caido","path":"/Users/me/Security-Ops/.mcp.json","detail":"\"caido\" in ~/Security-Ops/.mcp.json runs jit inside jit",
    "action":"`jit migrate ~/Security-Ops/.mcp.json` to collapse each to one wrapper","fixes":[{"command":
    "jit migrate ~/Security-Ops/.mcp.json","argv":["migrate","/Users/me/Security-Ops/.mcp.json"],"destructive":false,
    "presence":false}]},{"kind":"mcp_nested","profile":"mcp-google-workspace-investigate","path":
    "/Users/me/Security-Ops/.mcp.json","detail":
    "\"google-workspace-investigate\" in ~/Security-Ops/.mcp.json runs jit inside jit","action":
    "`jit migrate ~/Security-Ops/.mcp.json` to collapse each to one wrapper","fixes":[{"command":
    "jit migrate ~/Security-Ops/.mcp.json","argv":["migrate","/Users/me/Security-Ops/.mcp.json"],"destructive":false,
    "presence":false}]},{"kind":"mcp_nested","profile":"mcp-okta-mcp-server","path":"/Users/me/Security-Ops/.mcp.json","detail":
    "\"okta-mcp-server\" in ~/Security-Ops/.mcp.json runs jit inside jit","action":
    "`jit migrate ~/Security-Ops/.mcp.json` to collapse each to one wrapper","fixes":[{"command":
    "jit migrate ~/Security-Ops/.mcp.json","argv":["migrate","/Users/me/Security-Ops/.mcp.json"],"destructive":false,
    "presence":false}]},{"kind":"no_known_tool","profile":"k8s-docker-desktop","scope":"global","path":
    "/Users/me/.jit/profiles/k8s-docker-desktop.yaml","detail":"no known tool; 2 secrets, both missing","action":
    "`jit profile rm k8s-docker-desktop` if you no longer use it","fixes":[{"command":"jit profile rm k8s-docker-desktop",
    "argv":["profile","rm","k8s-docker-desktop"],"destructive":true,"presence":true}],"secrets":2,"secrets_missing":2},{"kind":
    "no_known_tool","profile":"token","scope":"global","path":"/Users/me/.jit/profiles/token.yaml","detail":
    "no known tool; 1 secret","action":"`jit profile rm token` if you no longer use it","fixes":[{"command":
    "jit profile rm token","argv":["profile","rm","token"],"destructive":true,"presence":true}],"secrets":1,"origin":
    "/Users/me/token.txt"}]}
    """#
}
