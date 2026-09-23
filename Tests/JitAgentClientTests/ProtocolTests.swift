// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class ProtocolTests: XCTestCase {
    func testStatusResponseDecodes() throws {
        let json = """
        {"ok":true,"protocol":1,"unlocked":true,"expires_in_seconds":252,
         "last_unlock":{"unix_time":1789200000,"kind":"unlock","op":"unwrap","by":"jit run --profile mcp-jamf","launched_by":"claude"},
         "unexpected_field":"ignored"}
        """
        let r = try JSONDecoder().decode(AgentResponse.self, from: Data(json.utf8))
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.protocolVersion, 1)
        XCTAssertEqual(r.unlocked, true)
        XCTAssertEqual(r.expiresInSeconds, 252)
        XCTAssertEqual(r.lastUnlock?.launchedBy, "claude")
    }

    func testGrantDecodes() throws {
        let json = """
        {"ok":true,"grants":[{"id":"g-7f3a2c81","pid":48211,"name":"claude","anchor":"iTerm2",
          "profiles":["jamf","aws-ci"],"secrets":["jamf/token","aws/ci"],
          "created_unix":1789200000,"expires_unix":1789228800,"serves":14,"root_alive":true}]}
        """
        let r = try JSONDecoder().decode(AgentResponse.self, from: Data(json.utf8))
        let g = try XCTUnwrap(r.grants?.first)
        XCTAssertEqual(g.id, "g-7f3a2c81")
        XCTAssertEqual(g.anchor, "iTerm2")
        XCTAssertEqual(g.profiles, ["jamf", "aws-ci"])
        XCTAssertEqual(g.serves, 14)
        XCTAssertTrue(g.rootAlive)
    }

    func testHistoryArrivesUnderEvents() throws {
        // The Go response field is Events (json "events"); a client reading
        // "history" would silently see an empty tail forever.
        let json = #"{"ok":true,"events":[{"unix_time":1789200000,"kind":"lock","cause":"5 min idle timeout"}]}"#
        let r = try JSONDecoder().decode(AgentResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.events?.first?.cause, "5 min idle timeout")
    }

    func testStatusCeilingAndSettingsDecodeWhenPresent() throws {
        let json = #"""
        {"ok":true,"unlocked":true,"expires_in_seconds":252,
         "ceiling_in_seconds":26520,"ttl_seconds":300,"consent_enabled":true}
        """#
        let r = try JSONDecoder().decode(AgentResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.ceilingInSeconds, 26520)
        XCTAssertEqual(r.ttlSeconds, 300)
        XCTAssertEqual(r.consentEnabled, true)
        let old = try JSONDecoder().decode(AgentResponse.self, from: Data(#"{"ok":true,"unlocked":true}"#.utf8))
        XCTAssertNil(old.ceilingInSeconds, "an older agent omits the field; it must read as unknown, not zero")
    }

    func testRequestEncodesSnakeCaseAndOmitsNil() throws {
        let data = try JSONEncoder().encode(AgentRequest(op: .grantRevoke, grantID: "g-1"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["op"] as? String, "grant_revoke")
        XCTAssertEqual(obj["grant_id"] as? String, "g-1")
        XCTAssertNil(obj["min_protocol"])
    }

    func testGrantCreateEncodesEveryField() throws {
        let request = AgentRequest(
            op: .grantCreate,
            targetPID: 48211,
            grantProfiles: ["jamf", "aws-ci"],
            projectRoot: "/Users/me/app",
            ttlSeconds: 28800
        )
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(obj["op"] as? String, "grant_create")
        XCTAssertEqual(obj["target_pid"] as? Int, 48211)
        XCTAssertEqual(obj["grant_profiles"] as? [String], ["jamf", "aws-ci"])
        XCTAssertEqual(obj["project_root"] as? String, "/Users/me/app")
        XCTAssertEqual(obj["ttl_seconds"] as? Int, 28800)
    }

    func testTreeGrantEncodesNameAndExplicitAnchor() throws {
        let request = AgentRequest(
            op: .grantCreate,
            targetPID: 501,
            grantProfiles: ["jamf"],
            ttlSeconds: 3600,
            grantName: "claude",
            anchorExplicit: true
        )
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(obj["grant_name"] as? String, "claude")
        XCTAssertEqual(obj["anchor_explicit"] as? Bool, true)
        XCTAssertEqual(obj["target_pid"] as? Int, 501)
        let exact = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AgentRequest(
            op: .grantCreate,
            targetPID: 7
        ))) as? [String: Any]
        XCTAssertNil(exact?["anchor_explicit"], "an exact-process grant never claims an explicit anchor")
    }

    func testStandingGrantDecodesAndAnOldAgentStillRenders() throws {
        let json = """
        {"ok":true,"grants":[{"id":"g-1","pid":0,"name":"claude","anchor":"iTerm2",
          "anchor_path":"/Applications/iTerm.app/Contents/MacOS/iTerm2","standing":true,
          "profiles":["mcp-caido"],"profile_roots":[{"name":"mcp-caido","root":"/Users/me/Security-Ops"}],
          "secrets":["caido/url"],"rotated":["caido/url"],"created_unix":1789200000,"expires_unix":0,
          "serves":4,"last_serve_unix":1789203600,"root_alive":true}]}
        """
        let g = try XCTUnwrap(JSONDecoder().decode(AgentResponse.self, from: Data(json.utf8)).grants?.first)
        XCTAssertTrue(g.isStanding)
        XCTAssertEqual(g.anchorPath, "/Applications/iTerm.app/Contents/MacOS/iTerm2")
        XCTAssertEqual(g.profileRoots, [GrantProfile(name: "mcp-caido", root: "/Users/me/Security-Ops")])
        XCTAssertEqual(g.rotatedSecrets, ["caido/url"])
        XCTAssertEqual(g.lastServeUnix, 1_789_203_600)

        // Every new field is optional on decode: an older agent's grant
        // still renders, as a timed one with nothing rotated.
        let old = #"{"ok":true,"grants":[{"id":"g-2","pid":7,"profiles":[],"created_unix":1,"expires_unix":2,"root_alive":true}]}"#
        let g2 = try XCTUnwrap(JSONDecoder().decode(AgentResponse.self, from: Data(old.utf8)).grants?.first)
        XCTAssertFalse(g2.isStanding)
        XCTAssertEqual(g2.rotatedSecrets, [])
        XCTAssertNil(g2.lastServe)
    }

    func testStandingGrantEncodesRootsAndNoTTL() throws {
        let request = AgentRequest(
            op: .grantCreate, targetPID: 501, grantName: "claude", anchorExplicit: true,
            grantProfileRoots: [GrantProfile(name: "mcp-caido", root: "/Users/me/Security-Ops"), GrantProfile(name: "global-one")],
            standing: true
        )
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(obj["standing"] as? Bool, true)
        XCTAssertNil(obj["ttl_seconds"], "standing and a deadline are exclusive")
        XCTAssertNil(obj["grant_profiles"], "the per-folder field replaces the names-plus-one-root pair")
        let roots = try XCTUnwrap(obj["grant_profile_roots"] as? [[String: Any]])
        XCTAssertEqual(roots.count, 2)
        XCTAssertEqual(roots[0]["name"] as? String, "mcp-caido")
        XCTAssertEqual(roots[0]["root"] as? String, "/Users/me/Security-Ops")
        XCTAssertNil(roots[1]["root"], "a global profile sends no folder")
    }

    func testConsentAnswerEncodesIDAndDecision() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AgentRequest(
            op: .consentAnswer, consentID: "ab12", decision: .deny
        ))) as? [String: Any])
        XCTAssertEqual(json["op"] as? String, "consent_answer")
        XCTAssertEqual(json["consent_id"] as? String, "ab12")
        XCTAssertEqual(json["decision"] as? String, "deny")
        XCTAssertNil(json["broker"])
    }

    func testEventDecodesTheBrokeringFields() throws {
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(
            #"{"unix_time":1,"kind":"denied","by_pid":77,"by_likely":true,"consent_id":"ab12"}"#.utf8
        ))
        XCTAssertEqual(event.byPID, 77)
        XCTAssertEqual(event.byLikely, true)
        XCTAssertEqual(event.consentID, "ab12")
    }

    func testAppNeverSpeaksWrapOrUnwrap() {
        // The op set is the app's whole vocabulary. Keeping DEK ops out of it
        // is what guarantees no plaintext or key can reach this process.
        let ops = Set(AgentOp.allCases.map(\.rawValue))
        XCTAssertFalse(ops.contains("wrap"))
        XCTAssertFalse(ops.contains("unwrap"))
        XCTAssertFalse(ops.contains("reveal_pid"))
    }
}

extension ProtocolTests {
    /// A create must carry BOTH wire shapes. The per-folder field is what a
    /// current agent reads; the names-plus-one-root pair is all an older one
    /// understands, and sending only the new field made the bundled 2.2.6
    /// agent see no profiles and refuse every create — including the timed
    /// grants that worked before the field existed.
    func testACreateCarriesBothWireShapesSoAnOlderAgentStillWorks() throws {
        let client = AgentClient(socketPath: "/nonexistent")
        let same = [GrantProfile(name: "a", root: "/p"), GrantProfile(name: "b", root: "/p")]
        let legacy = try XCTUnwrap(AgentClient.legacyProfilesForTests(same))
        XCTAssertEqual(legacy.names, ["a", "b"])
        XCTAssertEqual(legacy.root, "/p")

        // Two folders cannot be said in the old shape at all, so it is
        // omitted rather than guessed: an older agent then refuses in its
        // own words instead of resolving from the wrong folder.
        let mixed = [GrantProfile(name: "a", root: "/p"), GrantProfile(name: "b", root: "/q")]
        XCTAssertNil(AgentClient.legacyProfilesForTests(mixed))

        // A global profile carries no folder, which is a root of nil, not a
        // disagreement.
        let global = [GrantProfile(name: "a"), GrantProfile(name: "b")]
        let g = try XCTUnwrap(AgentClient.legacyProfilesForTests(global))
        XCTAssertNil(g.root)
        _ = client
    }
}

extension ProtocolTests {
    /// The bytes on the wire, not the helper: a timed create must be readable
    /// by a 2.2.6 agent, which looks only at grant_profiles + project_root.
    func testTheTimedCreateOnTheWireIsReadableByA226Agent() throws {
        let profiles = [GrantProfile(name: "mcp-caido", root: "/Users/me/Security-Ops")]
        let legacy = AgentClient.legacyProfilesForTests(profiles)
        let request = AgentRequest(
            op: .grantCreate, targetPID: 501,
            grantProfiles: legacy?.names, projectRoot: legacy?.root,
            ttlSeconds: 28800, grantProfileRoots: profiles
        )
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        // What a 2.2.6 agent reads (grant.go: len(req.GrantProfiles) == 0,
        // then OnResolveGrant(req.GrantProfiles, req.ProjectRoot)).
        XCTAssertEqual(obj["grant_profiles"] as? [String], ["mcp-caido"], "a 2.2.6 agent refuses a create with no grant_profiles")
        XCTAssertEqual(obj["project_root"] as? String, "/Users/me/Security-Ops")
        XCTAssertEqual(obj["ttl_seconds"] as? Int, 28800)
        // And what a current agent prefers.
        XCTAssertEqual((obj["grant_profile_roots"] as? [[String: Any]])?.count, 1)
    }
}
