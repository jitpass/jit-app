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
        let json = #"{"ok":true,"events":[{"unix_time":1789200000,"kind":"lock","cause":"5m idle timeout"}]}"#
        let r = try JSONDecoder().decode(AgentResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.events?.first?.cause, "5m idle timeout")
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

    func testAppNeverSpeaksWrapOrUnwrap() {
        // The op set is the app's whole vocabulary. Keeping DEK ops out of it
        // is what guarantees no plaintext or key can reach this process.
        let ops = Set(AgentOp.allCases.map(\.rawValue))
        XCTAssertFalse(ops.contains("wrap"))
        XCTAssertFalse(ops.contains("unwrap"))
        XCTAssertFalse(ops.contains("reveal_pid"))
    }
}
