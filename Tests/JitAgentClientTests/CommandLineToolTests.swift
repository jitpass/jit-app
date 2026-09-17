// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class CommandLineToolTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("clt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func executable(_ relative: String) throws -> String {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    func testLinkedWhenPathResolvesIntoTheBundle() throws {
        let bundled = try executable("JitPass.app/Contents/MacOS/jit")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: bin.appendingPathComponent("jit").path, withDestinationPath: bundled)
        let state = CommandLineTool.state(bundled: bundled, path: "/nonexistent:\(bin.path)")
        XCTAssertEqual(state, .linked(bin.appendingPathComponent("jit").path))
    }

    func testOtherWhenAForeignJitComesFirst() throws {
        let bundled = try executable("JitPass.app/Contents/MacOS/jit")
        let foreign = try executable("local/bin/jit")
        let state = CommandLineTool.state(bundled: bundled, path: root.appendingPathComponent("local/bin").path)
        XCTAssertEqual(state, .other(foreign))
    }

    func testMissingWhenNoJitOnPath() throws {
        let bundled = try executable("JitPass.app/Contents/MacOS/jit")
        XCTAssertEqual(CommandLineTool.state(bundled: bundled, path: root.path), .missing)
        XCTAssertEqual(CommandLineTool.state(bundled: bundled, path: ""), .missing)
    }

    func testLinkTargetFallsBackToUsrLocalWithAdmin() {
        // Neither usual directory is on this PATH, so the answer is the
        // password path whatever the machine has installed.
        let target = CommandLineTool.linkTarget(path: "/nowhere:/else")
        XCTAssertEqual(target.directory, "/usr/local/bin")
        XCTAssertTrue(target.needsAdmin)
    }
}
