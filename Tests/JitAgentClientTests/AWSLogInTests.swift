// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The aws row's "Log In as <profile> in Terminal": the command handed to
/// the terminal, and when the items appear. And the AWS credential cache's
/// events, as History words them.
final class AWSLogInTests: XCTestCase {
    private func aws(_ extra: String) throws -> ToolRecord {
        try JSONDecoder().decode(
            ToolRecord.self,
            from: Data(#"{"tool":"aws","kind":"native","native_category":"aws","vault_secrets":1\#(extra)}"#.utf8)
        )
    }

    func testTheCommandIsJitsLoginForThatProfile() {
        XCTAssertEqual(ToolRecord.ssoLoginCommand("dev"), "jit aws-sso login --profile dev")
        XCTAssertEqual(ToolRecord.ssoLoginCommand("team.prod-1"), "jit aws-sso login --profile team.prod-1")
    }

    /// The command runs in the terminal's shell: a space or a quote in a
    /// profile name must not split it into two words.
    func testAProfileNameWithASpaceOrAQuoteIsQuotedForTheShell() {
        XCTAssertEqual(ToolRecord.ssoLoginCommand("my prod"), "jit aws-sso login --profile 'my prod'")
        XCTAssertEqual(ToolRecord.ssoLoginCommand("dana's"), #"jit aws-sso login --profile 'dana'\''s'"#)
        XCTAssertEqual(JobDraft.split(ToolRecord.ssoLoginCommand("dana's box")), ["jit", "aws-sso", "login", "--profile", "dana's box"])
    }

    func testAnItemPerProfileWheneverASignInWasEverSealed() throws {
        let signedIn = try aws(#","sso_profiles":["dev","prod"],"sso_signed_in":true"#)
        XCTAssertEqual(
            signedIn.ssoLogIns.map(\.profile),
            ["dev", "prod"],
            "signed-in is the whole store's: one profile can still need a login"
        )
        let signedOut = try aws(#","sso_profiles":["dev","prod"],"sso_signed_in":false"#)
        XCTAssertEqual(signedOut.ssoLogIns.map(\.profile), ["dev", "prod"])
        XCTAssertEqual(signedOut.ssoLogIns.map(\.command), ["jit aws-sso login --profile dev", "jit aws-sso login --profile prod"])
    }

    func testNoItemWhenNothingWasEverSealed() throws {
        XCTAssertEqual(try aws(#","sso_profiles":["dev"]"#).ssoLogIns, [], "sso_signed_in absent")
        XCTAssertEqual(try aws("").ssoLogIns, [])
    }

    /// jit lists `aws login` console profiles in sso_profiles too, and
    /// `jit aws-sso login` picks the flow itself: the same command.
    func testAConsoleProfileGetsTheSameCommandAsAnSSOOne() throws {
        let row = try aws(#","sso_profiles":["sso-dev","console-admin"],"sso_signed_in":true"#)
        XCTAssertEqual(row.ssoLogIns, [
            SSOLogIn(profile: "sso-dev", command: "jit aws-sso login --profile sso-dev"),
            SSOLogIn(profile: "console-admin", command: "jit aws-sso login --profile console-admin")
        ])
    }

    // MARK: - The AWS credential cache in History

    /// A cache hit is jit's aws_cache_get use event: worded as jit's
    /// history words it, never as a secret "used".
    func testAnAWSCacheHitReadsAsCachedCredentials() {
        let hit = SessionEvent(unixTime: 0, kind: "use", op: "aws_cache_get", by: "/usr/local/bin/aws", labels: ["aws-sso:dev"])
        XCTAssertEqual(AuditReport.title(for: hit), "aws read cached AWS credentials (aws-sso:dev)")
        let bare = SessionEvent(unixTime: 0, kind: "use", op: "aws_cache_get", labels: ["aws-sso:dev"])
        XCTAssertEqual(AuditReport.title(for: bare), "read cached AWS credentials (aws-sso:dev)")
    }

    /// jit 2.4.0 records the cache's fills, clears and refused fills,
    /// worded as jit's DescribeUse words them; a refused fill is the
    /// planting attempt the proof stops, and reads as one.
    func testTheAWSCachesOtherEventsAreWordedAsJitWordsThem() {
        let put = SessionEvent(unixTime: 0, kind: "use", op: "aws_cache_put", by: "/usr/local/bin/aws", labels: ["aws-sso:dev"])
        XCTAssertEqual(AuditReport.title(for: put), "aws cached AWS credentials (aws-sso:dev)")
        let clear = SessionEvent(unixTime: 0, kind: "use", op: "aws_cache_clear")
        XCTAssertEqual(AuditReport.title(for: clear), "cleared cached AWS credentials")
        let refused = SessionEvent(unixTime: 0, kind: "error", op: "aws-cache-refused", by: "/usr/bin/python3", labels: ["aws-sso:evil"])
        XCTAssertEqual(AuditReport.title(for: refused), "refused AWS credentials from python3 (aws-sso:evil)")
    }
}
