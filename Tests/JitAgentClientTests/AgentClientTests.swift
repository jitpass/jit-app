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

    func testPathTooLongIsAnError() {
        let long = "/tmp/" + String(repeating: "x", count: 200)
        XCTAssertThrowsError(try AgentClient(socketPath: long, timeout: 1).status()) { error in
            guard case .io = error as? AgentClientError else {
                return XCTFail("expected io error, got \(error)")
            }
        }
    }
}
