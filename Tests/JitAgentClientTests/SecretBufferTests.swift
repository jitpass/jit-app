// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class SecretBufferTests: XCTestCase {
    func testConsumingZeroesTheCallersData() {
        var data = Data("sk_live_example".utf8)
        let buffer = SecretBuffer(consuming: &data)
        XCTAssertEqual(buffer.text, "sk_live_example")
        XCTAssertEqual(buffer.count, 15)
        XCTAssertTrue(data.allSatisfy { $0 == 0 }, "the source Data must be overwritten, not merely copied")
    }

    func testWipeOverwritesAndEmptiesTheText() {
        var data = Data("hunter2".utf8)
        let buffer = SecretBuffer(consuming: &data)
        buffer.wipe()
        XCTAssertTrue(buffer.isWiped)
        XCTAssertTrue(buffer.storageIsZero)
        XCTAssertEqual(buffer.text, "")
        XCTAssertEqual(buffer.count, 0)
        buffer.wipe() // idempotent
        XCTAssertTrue(buffer.storageIsZero)
    }

    func testEmptyValueIsSafe() {
        var data = Data()
        let buffer = SecretBuffer(consuming: &data)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.text, "")
        buffer.wipe()
        XCTAssertTrue(buffer.storageIsZero)
    }

    func testMultiLineValueRoundTrips() {
        let pem = "-----BEGIN KEY-----\nabc\n-----END KEY-----"
        var data = Data(pem.utf8)
        let buffer = SecretBuffer(consuming: &data)
        XCTAssertEqual(buffer.text, pem)
    }
}
