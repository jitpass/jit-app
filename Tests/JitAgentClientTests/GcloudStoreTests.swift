// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// jit's sealed gcloud store (jitpass/jit design/gcloud-sealed-store.md): a
/// wrap kind "store" that seals gcloud's login in the vault and shims the
/// whole family that reads it, wrapped and unwrapped as one.
final class GcloudStoreTests: XCTestCase {
    /// The catalog as `jit wrap list --all --format json` prints it on the
    /// branch: gcloud is a store row now, with four family members.
    static let listing = try? JSONDecoder().decode(ToolListing.self, from: Data(#"""
    {"tools":[
      {"tool":"gcloud","kind":"store","store":"gcloud","store_path":"gcloud-cli/store","catalog":true,
       "installed_path":"/opt/sdk/bin/gcloud",
       "doc":"Google Cloud CLI login (refresh token), sealed in the vault and unsealed per run","verify_hint":"gcloud auth list"},
      {"tool":"bq","kind":"store","store":"gcloud","store_path":"gcloud-cli/store","catalog":true,
       "installed_path":"/opt/sdk/bin/bq","verify_hint":"bq version"},
      {"tool":"gsutil","kind":"store","store":"gcloud","store_path":"gcloud-cli/store","catalog":true,
       "installed_path":"/opt/sdk/bin/gsutil"},
      {"tool":"docker-credential-gcloud","kind":"store","store":"gcloud","store_path":"gcloud-cli/store","catalog":true},
      {"tool":"git-credential-gcloud","kind":"store","store":"gcloud","store_path":"gcloud-cli/store","catalog":true},
      {"tool":"sops","kind":"grant","with":"sops","catalog":true,"installed_path":"/opt/homebrew/bin/sops",
       "verify_hint":"sops --decrypt x","verify_prints_secret":true}
    ]}
    """#.utf8))

    /// One finding line (NDJSON, one object per line) and a summary.
    static func scan(_ finding: String) throws -> ScanReport {
        let line = finding.replacingOccurrences(of: "\n", with: " ")
        let summary = #"{"record_type":"scan_summary","total_findings":1,"risk_level":"high","exposure_score":0,"#
            + #""secrets_total":1,"secrets_protected":0,"secrets_migratable":0,"files_scanned":1}"#
        return try ScanReport.parse(Data((line + "\n" + summary).utf8))
    }

    // MARK: - Listing

    func testAStoreRowDecodesItsStoreAndCountsAsNeitherGrantNorNative() throws {
        let gcloud = try XCTUnwrap(Self.listing?.tool(named: "gcloud"))
        XCTAssertTrue(gcloud.isStore)
        XCTAssertEqual(gcloud.store, "gcloud")
        XCTAssertFalse(gcloud.isGrant)
        XCTAssertFalse(gcloud.isNative)
        XCTAssertFalse(gcloud.verifyMayPrintSecret, "gcloud auth list prints accounts, not a token")
        XCTAssertEqual(gcloud.readPaths, ["gcloud-cli/store"], "its reads are the sealed store's")
    }

    /// One wrap takes every installed member, the namesake first; the
    /// helpers that are not installed are not in it.
    func testTheFamilyIsTheInstalledMembersNamesakeFirst() throws {
        let listing = try XCTUnwrap(Self.listing)
        XCTAssertEqual(listing.family(of: "bq"), ["gcloud", "bq", "gsutil"])
        XCTAssertEqual(listing.family(of: "gcloud"), ["gcloud", "bq", "gsutil"])
        XCTAssertEqual(listing.family(of: "sops"), ["sops"], "any other kind is its own family")
        XCTAssertEqual(NameList.spoken(listing.family(of: "gsutil")), "gcloud, bq and gsutil")
    }

    /// bq and gsutil are wrapped by gcloud's row, so they are not three
    /// more things to protect.
    func testOnlyTheNamesakeStandsForTheFamilyAmongToolsToWrap() throws {
        let listing = try XCTUnwrap(Self.listing)
        XCTAssertEqual(listing.toWrap.map(\.tool), ["gcloud", "sops"])
        let bq = try XCTUnwrap(listing.tool(named: "bq"))
        XCTAssertFalse(listing.standsAlone(bq))
        // Without gcloud installed, bq is the only way to the wrap.
        var lone = listing
        lone.tools.removeAll { $0.tool == "gcloud" }
        XCTAssertTrue(lone.standsAlone(bq))
    }

    /// Scan points the store at `jit wrap gcloud`; every member's row
    /// finds that same key.
    func testEveryMemberFindsTheStoresFinding() throws {
        let scan = try Self.scan(#"""
        {"record_type":"finding","record_id":"f1","finding_type":"credential_file","severity":"high",
         "file_path":"/Users/me/.config/gcloud/credentials.db","evidence":"gcloud login","remedy":"wrap",
         "fix_command":"jit wrap gcloud","archived":false,"test_fixture":false}
        """#)
        let bq = try XCTUnwrap(Self.listing?.tool(named: "bq"))
        XCTAssertEqual(bq.wrapName, "gcloud")
        XCTAssertEqual(bq.keyState(scan: scan), .found("/Users/me/.config/gcloud/credentials.db"))
    }

    func testAStoreCardSaysWhatItUnsealsAndAFamilyReadIsNotAnotherPrograms() throws {
        var gcloud = try XCTUnwrap(Self.listing?.tool(named: "gcloud"))
        gcloud.wrapped = true
        gcloud.shim = "ok"
        let activity = ToolActivity(reads: 3, lastRead: Date(timeIntervalSince1970: 1000), readers: ["gcloud", "bq"])
        let card = ToolCard.make(
            gcloud, sessions: [], activity: activity, family: ["gcloud", "bq", "gsutil"], now: Date(timeIntervalSince1970: 2000)
        )
        XCTAssertEqual(card.detail, "unseals the gcloud login per run")
        XCTAssertTrue(card.fact.hasSuffix("no other program"), card.fact)
    }

    /// A listing without store_path has nothing to count: the app does
    /// not guess the vault path.
    func testAStoreRowWithoutItsVaultPathHasNoReadsToCount() throws {
        let row = try JSONDecoder().decode(ToolRecord.self, from: Data(#"""
        {"tool":"bq","kind":"store","store":"gcloud","wrapped":true}
        """#.utf8))
        XCTAssertNil(row.storePath)
        XCTAssertEqual(row.readPaths, [])
    }

    /// az (jit #219) is a store of its own, a family of one: the same row,
    /// reads and scan finding as gcloud's, under its own name.
    func testAzIsAStoreFamilyOfItsOwn() throws {
        let listing = try JSONDecoder().decode(ToolListing.self, from: Data(#"""
        {"tools":[{"tool":"az","kind":"store","store":"az","store_path":"azure-cli/store","catalog":true,
          "installed_path":"/opt/homebrew/bin/az"}]}
        """#.utf8))
        let az = try XCTUnwrap(listing.tool(named: "az"))
        XCTAssertEqual(listing.family(of: "az"), ["az"])
        XCTAssertEqual(az.readPaths, ["azure-cli/store"])
        let scan = try Self.scan(#"""
        {"record_type":"finding","record_id":"f3","finding_type":"credential_file","severity":"high",
         "file_path":"/Users/me/.azure/msal_token_cache.json","evidence":"az login","remedy":"wrap",
         "fix_command":"jit wrap az","archived":false,"test_fixture":false}
        """#)
        XCTAssertEqual(az.keyState(scan: scan), .found("/Users/me/.azure/msal_token_cache.json"))
    }

    // MARK: - Wrap result

    func testAStoreWrapNamesTheFamilyAndWhereTheLoginWent() throws {
        let report = try WrapReport.parse(Data(#"""
        {"tool":"gcloud","kind":"store","wrapped":true,"shim":"~/.jit/shims/gcloud","store":"gcloud",
         "shims":["~/.jit/shims/gcloud","~/.jit/shims/bq","~/.jit/shims/gsutil"],
         "vaulted":["gcloud-cli/store"],"errors":[],"report":"Wrapped gcloud, bq, gsutil"}
        """#.utf8))
        let sheet = ChangeSheet.wrapped(report, verify: true)
        XCTAssertEqual(sheet.title, "Wrapped gcloud, bq and gsutil")
        XCTAssertEqual(sheet.sentence, "gcloud's login is in the vault. Each run unseals it for that run only.")
        XCTAssertEqual(sheet.notes.map(\.name), ["gcloud's login moved to the vault", "gcloud, bq and gsutil now run through jit"])
        XCTAssertEqual(sheet.notes[0].fact, "Nothing of it is left on disk · gcloud-cli/store")
        XCTAssertFalse(sheet.notes.contains { $0.name.contains("secret") }, "the store is one login, not a count of secrets")
        XCTAssertEqual(sheet.verify, "gcloud")
    }

    /// Wrapped before any login: the next one is caught, and the sheet
    /// says there is nothing in the vault yet.
    func testAStoreWrapBeforeAnyLoginSaysTheNextOneIsCaught() throws {
        let report = try WrapReport.parse(Data(#"""
        {"tool":"bq","kind":"store","wrapped":true,"store":"gcloud","shims":["~/.jit/shims/bq","~/.jit/shims/gcloud"],
         "store_logged_out":true,"vaulted":[],"errors":[],"report":""}
        """#.utf8))
        let sheet = ChangeSheet.wrapped(report)
        XCTAssertEqual(sheet.title, "Wrapped gcloud and bq", "the namesake first, whichever member was named")
        XCTAssertEqual(sheet.sentence, "Each gcloud login from now on is kept in the vault, not on disk.")
        XCTAssertEqual(sheet.notes.first?.mark, .left)
        XCTAssertEqual(sheet.notes.first?.name, "No gcloud login yet")
    }

    func testAStoreWrapOfASealedStoreSaysItWasAlreadyThere() {
        let report = WrapReport(tool: "gcloud", kind: "store", wrapped: true, store: "gcloud", shims: ["~/.jit/shims/gcloud"])
        let sheet = ChangeSheet.wrapped(report)
        XCTAssertEqual(sheet.title, "Wrapped gcloud")
        XCTAssertEqual(sheet.notes.map(\.name), ["gcloud's login was already in the vault", "gcloud now runs through jit"])
    }

    // MARK: - Remove JitPass

    func testTheRestorePlanSetsTheSealedLoginApart() throws {
        let plan = try UninstallPlan.parse(Data(#"""
        {"restore_plan":{"restore":[
          {"path":"/Users/u/.aws/config","kind":"backup"},
          {"path":"/Users/u/.config/gcloud/credentials.db","kind":"store"}]},
         "secrets":2,"key_present":true}
        """#.utf8))
        XCTAssertEqual(plan.stores.map(\.path), ["/Users/u/.config/gcloud/credentials.db"])
        XCTAssertEqual(plan.restore.count, 2, "still a file Remove puts back")
    }

    // MARK: - Vault delete

    /// `jit vault rm gcloud-cli/store` names the wrap manifest as the
    /// store's user. It is no jit:// pointer: the wrapped tools log out.
    func testDeletingTheSealedStoreSaysTheWrappedToolsLogOut() throws {
        let plan = try VaultRmPlan.parse(Data(#"""
        {"paths":["gcloud-cli/store"],"refused":true,
         "in_use":[{"path":"gcloud-cli/store","pointer_file":"/Users/me/.jit/wrap.json","store":"gcloud"}]}
        """#.utf8))
        let dialog = plan.confirmation(home: "/Users/me")
        XCTAssertTrue(dialog.message.contains("the tools wrapped in ~/.jit/wrap.json unseal it on each run"), dialog.message)
        XCTAssertTrue(dialog.message.contains("The tools wrapped in ~/.jit/wrap.json are signed out"), dialog.message)
        XCTAssertFalse(dialog.message.contains("jit://"), dialog.message)
        XCTAssertEqual(dialog.button, "Delete and Break Wrapped Tools")
    }

    /// jit names ~/.aws/config as the user of the sealed SSO login, with
    /// its store: the profiles sign out, no jit:// pointer breaks.
    func testDeletingTheSealedSSOLoginSaysTheProfilesSignOut() throws {
        let plan = try VaultRmPlan.parse(Data(#"""
        {"paths":["aws-sso/cache"],"refused":true,
         "in_use":[{"path":"aws-sso/cache","pointer_file":"/Users/me/.aws/config","store":"aws-sso"}]}
        """#.utf8))
        let dialog = plan.confirmation(home: "/Users/me")
        XCTAssertTrue(dialog.message.contains("• the AWS profiles in ~/.aws/config unseal it on each run"), dialog.message)
        XCTAssertTrue(dialog.message.contains("The AWS profiles in ~/.aws/config are signed out"), dialog.message)
        XCTAssertFalse(dialog.message.contains("jit://"), dialog.message)
        XCTAssertEqual(dialog.button, "Delete and Break AWS Profiles")
    }

    /// az's sealed store (jit #219) is a wrapped family like gcloud's: any
    /// store but AWS's is unsealed by the tools in jit's wrap manifest.
    func testDeletingAnotherWrappedStoreSaysTheWrappedToolsSignOut() throws {
        let plan = try VaultRmPlan.parse(Data(#"""
        {"paths":["azure-cli/store"],"refused":true,
         "in_use":[{"path":"azure-cli/store","pointer_file":"/Users/me/.jit/wrap.json","store":"az"}]}
        """#.utf8))
        let dialog = plan.confirmation(home: "/Users/me")
        XCTAssertTrue(dialog.message.contains("• the tools wrapped in ~/.jit/wrap.json unseal it on each run"), dialog.message)
        XCTAssertEqual(dialog.button, "Delete and Break Wrapped Tools")
    }

    /// A pointer file without a store is still a jit:// pointer, whatever
    /// its name.
    func testAPointerFileWithoutAStoreKeepsItsPointerWording() throws {
        let plan = try VaultRmPlan.parse(Data(#"""
        {"paths":["aws/key"],"refused":true,"in_use":[{"path":"aws/key","pointer_file":"/Users/me/.aws/config"}]}
        """#.utf8))
        let dialog = plan.confirmation(home: "/Users/me")
        XCTAssertTrue(dialog.message.contains("~/.aws/config points at it (jit://)"), dialog.message)
    }

    // MARK: - AWS SSO

    func testTheAwsRowSaysWhetherItsSSOLoginIsSealed() throws {
        let listing = try JSONDecoder().decode(ToolListing.self, from: Data(#"""
        {"tools":[
          {"tool":"aws","kind":"native","native_category":"aws","wrapped":false,"vault_secrets":2,
           "sso_profiles":["dev","prod"],"sso_signed_in":true},
          {"tool":"kubectl","kind":"native","native_category":"kube","vault_secrets":1}
        ]}
        """#.utf8))
        let aws = try XCTUnwrap(listing.tool(named: "aws"))
        XCTAssertEqual(aws.ssoProfiles, ["dev", "prod"])
        XCTAssertEqual(aws.ssoSignedIn, true)
        let card = ToolCard.make(aws, sessions: [], activity: nil)
        XCTAssertTrue(card.fact.hasSuffix(" · signed in to AWS · dev and prod use it"), card.fact)
        var out = aws
        out.ssoSignedIn = false
        XCTAssertTrue(ToolCard.make(out, sessions: [], activity: nil).fact.hasSuffix(" · signed out of AWS"))
        let kubectl = try XCTUnwrap(listing.tool(named: "kubectl"))
        XCTAssertNil(kubectl.ssoSignedIn, "never sealed: nothing to say, and no Sign Out")
        XCTAssertFalse(ToolCard.make(kubectl, sessions: [], activity: nil).fact.contains("SSO"))
    }

    /// A cache hit is jit's aws_cache_get use event: worded as jit's
    /// history words it, never as a secret "used".
    func testAnAWSCacheHitReadsAsCachedCredentials() {
        let hit = SessionEvent(unixTime: 0, kind: "use", op: "aws_cache_get", by: "/usr/local/bin/aws", labels: ["aws-sso:dev"])
        XCTAssertEqual(AuditReport.title(for: hit), "aws read cached AWS credentials (aws-sso:dev)")
        let bare = SessionEvent(unixTime: 0, kind: "use", op: "aws_cache_get", labels: ["aws-sso:dev"])
        XCTAssertEqual(AuditReport.title(for: bare), "read cached AWS credentials (aws-sso:dev)")
    }

    /// Two sealed logins, gcloud's and AWS SSO's, both come back from the
    /// vault on Remove.
    func testTwoSealedLoginsAreCountedApart() throws {
        let plan = try UninstallPlan.parse(Data(#"""
        {"restore_plan":{"restore":[
          {"path":"/Users/u/.config/gcloud/credentials.db","kind":"store"},
          {"path":"/Users/u/.aws/sso/cache","kind":"store"}]},
         "secrets":2,"key_present":true}
        """#.utf8))
        XCTAssertEqual(plan.stores.count, 2)
    }

    // MARK: - Doctor

    /// jit's wrap_store findings: advisory, a login on disk rather than a
    /// broken tool, each with the one command its action names.
    func testTheStoresDoctorFindingsAreALoginOnDiskNotABrokenTool() throws {
        let board = try DoctorBoardTests.board(#"""
        {"ok":true,"schema_version":2,"problems":[
          {"kind":"wrap","detail":"bq: shim symlink missing, `jit wrap gcloud` reinstalls it",
           "fixes":[{"command":"jit wrap gcloud","argv":["wrap","gcloud"]}]}
        ],"warnings":[
          {"kind":"wrap_store","path":"/Users/me/.config/gcloud",
           "detail":"gcloud: the login is back in plaintext in ~/.config/gcloud (something logged in without the shim)",
           "action":"`jit wrap gcloud` seals it again",
           "fixes":[{"command":"jit wrap gcloud","argv":["wrap","gcloud"],"destructive":false}]},
          {"kind":"wrap_store","path":"/Users/me/Library/Application Support/jitpass/gcloud-run",
           "detail":"gcloud: 1 folder where an interrupted run left the login unsealed in ~/Library/Application Support/jitpass/gcloud-run",
           "action":"`jit service restart` removes it now; the next gcloud run would too",
           "fixes":[{"command":"jit service restart","argv":["service","restart"],"destructive":false}]}
        ]}
        """#)
        let text = DoctorBoardTests.render(board)
        XCTAssertEqual(board.cards(in: .recommended).map(\.title), ["A sealed login is back on disk"], text)
        XCTAssertTrue(text.contains("[Seal Again]"), text)
        XCTAssertTrue(text.contains("[Restart Service]"), text)
        XCTAssertEqual(board.cards(in: .broken).map(\.title), ["Broken wrapped tools"], "a missing shim is still a broken tool")
    }

    func testStoreActionsRunTheCommandsJitNamed() {
        let item = DoctorItem(
            kind: "wrap_store", scope: nil, profile: nil, variable: nil, path: "/Users/me/.config/gcloud",
            detail: "gcloud: the login is back in plaintext in ~/.config/gcloud (something logged in without the shim)",
            action: "`jit wrap gcloud` seals it again",
            fixes: [DoctorFix(command: "jit wrap gcloud", argv: ["wrap", "gcloud"], destructive: false)]
        )
        let actions = DoctorAdvice.actions(for: item)
        XCTAssertEqual(actions.map(\.title), ["Seal Again"])
        XCTAssertEqual(actions.first?.argv, [["wrap", "gcloud"]])
        XCTAssertEqual(actions.first?.destructive, false)
    }

    // MARK: - Scan

    func testTheGoogleTokenNamesReadAsVendors() throws {
        let scan = try Self.scan(#"""
        {"record_type":"finding","record_id":"f2","finding_type":"exposed_secret","severity":"high",
         "file_path":"/Users/me/.config/gcloud/logs/2026.10.02/10.00.log",
         "evidence":"value matches Google OAuth Refresh Token's known token format","remedy":"manual",
         "archived":false,"test_fixture":false}
        """#)
        XCTAssertEqual(scan.findings.first?.vendorName, "Google OAuth Refresh Token")
    }
}
