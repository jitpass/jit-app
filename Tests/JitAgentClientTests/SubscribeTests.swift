// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class SubscribeTests: XCTestCase {
    private var path = ""

    override func setUp() {
        path = NSTemporaryDirectory() + "jitpass-sub-\(UUID().uuidString.prefix(8)).sock"
    }

    override func tearDown() {
        unlink(path)
    }

    private let ack = #"{"ok":true,"protocol":1}"#
    private let unlock = #"{"unix_time":1789200000,"kind":"unlock","op":"unwrap","by":"aws s3 ls"}"#
    private let lock = #"{"unix_time":1789200300,"kind":"lock","cause":"5m idle timeout"}"#

    func testEventsArriveInOrderThenTheStreamEnds() throws {
        let server = try FakeAgent(path: path, stream: [unlock, lock]) { request in
            XCTAssertEqual(request.op, .subscribe)
            return self.ack
        }
        defer { server.stop() }
        let ended = expectation(description: "onEnd")
        let received = Locked<[String]>([])
        let sub = AgentClient(socketPath: path).subscribe(
            onEvent: { event in received.append(event.kind) },
            onEnd: { error in
                XCTAssertNil(error)
                ended.fulfill()
            }
        )
        defer { sub.cancel() }
        wait(for: [ended], timeout: 5)
        XCTAssertEqual(received.value, ["unlock", "lock"])
    }

    func testBrokerFlagRidesTheSubscribeRequest() throws {
        let sent = Locked<[Bool?]>([])
        let server = try FakeAgent(path: path, stream: []) { request in
            sent.append(request.broker)
            return self.ack
        }
        defer { server.stop() }
        let ended = expectation(description: "onEnd")
        let sub = AgentClient(socketPath: path).subscribe(broker: true, onEvent: { _ in }, onEnd: { _ in ended.fulfill() })
        defer { sub.cancel() }
        wait(for: [ended], timeout: 5)
        XCTAssertEqual(sent.value, [true])
    }

    func testRefusalSurfacesAsAnError() throws {
        let server = try FakeAgent(path: path) { _ in #"{"ok":false,"error":"subscribe: this request needs agent protocol 9"}"# }
        defer { server.stop() }
        let ended = expectation(description: "onEnd")
        let sub = AgentClient(socketPath: path).subscribe(
            onEvent: { _ in XCTFail("no events after a refusal") },
            onEnd: { error in
                XCTAssertEqual(error as? AgentClientError, .agent("subscribe: this request needs agent protocol 9"))
                ended.fulfill()
            }
        )
        defer { sub.cancel() }
        wait(for: [ended], timeout: 5)
    }

    func testCancelStopsAHeldOpenStreamWithoutOnEnd() throws {
        let server = try FakeAgent(path: path, stream: [unlock], holdOpen: true) { _ in self.ack }
        defer { server.stop() }
        let first = expectation(description: "first event")
        let sub = AgentClient(socketPath: path).subscribe(
            onEvent: { _ in first.fulfill() },
            onEnd: { _ in XCTFail("onEnd must not fire after cancel") }
        )
        wait(for: [first], timeout: 5)
        sub.cancel()
        XCTAssertTrue(sub.isCancelled)
        // Give a wrongly-fired onEnd a moment to show up.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    func testNotRunningEndsImmediately() {
        let ended = expectation(description: "onEnd")
        let sub = AgentClient(socketPath: path).subscribe(
            onEvent: { _ in },
            onEnd: { error in
                XCTAssertEqual(error as? AgentClientError, .notRunning)
                ended.fulfill()
            }
        )
        defer { sub.cancel() }
        wait(for: [ended], timeout: 5)
    }
}

/// A tiny lock-protected box for values tests collect from another thread.
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) {
        stored = value
    }

    var value: T {
        lock.withLock { stored }
    }
}

extension Locked where T: RangeReplaceableCollection {
    func append(_ element: T.Element) {
        lock.withLock { stored.append(element) }
    }
}
