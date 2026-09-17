// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// Drives the real client against a fake agent on a temporary socket, so the
/// framing is tested end to end without jit installed.
final class AgentClientTests: XCTestCase {
    private var path = ""

    override func setUp() {
        path = NSTemporaryDirectory() + "jitpass-test-\(UUID().uuidString.prefix(8)).sock"
    }

    override func tearDown() {
        unlink(path)
    }

    func testNotRunningWhenNothingListens() {
        XCTAssertThrowsError(try AgentClient(socketPath: path, timeout: 1).status()) { error in
            XCTAssertEqual(error as? AgentClientError, .notRunning)
        }
    }

    func testStatusRoundTrip() throws {
        let server = try FakeAgent(path: path) { request in
            XCTAssertEqual(request.op, .status)
            return #"{"ok":true,"protocol":1,"unlocked":true,"expires_in_seconds":30}"#
        }
        defer { server.stop() }
        let r = try AgentClient(socketPath: path, timeout: 2).status()
        XCTAssertEqual(r.unlocked, true)
        XCTAssertEqual(r.expiresInSeconds, 30)
    }

    func testAgentErrorSurfaces() throws {
        let server = try FakeAgent(path: path) { _ in #"{"ok":false,"error":"no such grant"}"# }
        defer { server.stop() }
        XCTAssertThrowsError(try AgentClient(socketPath: path, timeout: 2).revokeGrant(id: "g-x")) { error in
            XCTAssertEqual(error as? AgentClientError, .agent("no such grant"))
        }
    }

    func testConsentListAndAnswerRoundTrip() throws {
        let seen = Locked<[AgentRequest]>([])
        let server = try FakeAgent(path: path) { request in
            seen.append(request)
            switch request.op {
            case .consentList:
                return #"{"ok":true,"events":[{"unix_time":1,"kind":"pending","consent_id":"ab12","by":"aws s3 ls"}]}"#
            default:
                return #"{"ok":true}"#
            }
        }
        defer { server.stop() }
        let client = AgentClient(socketPath: path, timeout: 2)
        let waiting = try client.consentList()
        XCTAssertEqual(waiting.map(\.consentID), ["ab12"])
        try client.answerConsent(id: "ab12", allow: true)
        XCTAssertEqual(seen.value.last?.op, .consentAnswer)
        XCTAssertEqual(seen.value.last?.consentID, "ab12")
        XCTAssertEqual(seen.value.last?.decision, .allow)
    }

    func testPathTooLongIsAnError() {
        let long = "/tmp/" + String(repeating: "x", count: 200)
        XCTAssertThrowsError(try AgentClient(socketPath: long, timeout: 1).status()) { error in
            guard case .io = error as? AgentClientError else {
                return XCTFail("expected io error, got \(error)")
            }
        }
    }
}
