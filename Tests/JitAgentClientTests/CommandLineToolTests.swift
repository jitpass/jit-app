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
        let bundled = try executable("JitPass.app/" + CommandLineTool.bundledRelativePath)
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: bin.appendingPathComponent("jit").path, withDestinationPath: bundled)
        let state = CommandLineTool.state(bundled: bundled, path: "/nonexistent:\(bin.path)")
        XCTAssertEqual(state, .linked(bin.appendingPathComponent("jit").path))
    }

    func testOtherWhenAForeignJitComesFirst() throws {
        let bundled = try executable("JitPass.app/" + CommandLineTool.bundledRelativePath)
        let foreign = try executable("local/bin/jit")
        let state = CommandLineTool.state(bundled: bundled, path: root.appendingPathComponent("local/bin").path)
        XCTAssertEqual(state, .other(foreign))
    }

    func testMissingWhenNoJitOnPath() throws {
        let bundled = try executable("JitPass.app/" + CommandLineTool.bundledRelativePath)
        XCTAssertEqual(CommandLineTool.state(bundled: bundled, path: root.path), .missing)
        XCTAssertEqual(CommandLineTool.state(bundled: bundled, path: ""), .missing)
    }

    func testBundledJitIsTheHelperBundlesMainExecutable() throws {
        let app = root.appendingPathComponent("JitPass.app")
        XCTAssertNil(CommandLineTool.bundledJit(in: app), "no helper yet: a dev build has none")
        let helperJit = try executable("JitPass.app/Contents/Helpers/JitPassAgent.app/Contents/MacOS/jit")
        XCTAssertEqual(CommandLineTool.bundledJit(in: app), helperJit)
    }

    /// Every install made before jit moved into its helper bundle has a PATH
    /// link naming the old place, Contents/MacOS/jit, which the bundle keeps
    /// as a symlink to the helper. That link must still read as this app's
    /// jit, not as some other copy, or Settings would offer to replace it.
    func testALinkToTheOldPathStillCountsAsLinked() throws {
        let helperJit = try executable("JitPass.app/" + CommandLineTool.bundledRelativePath)
        let oldPath = root.appendingPathComponent("JitPass.app/Contents/MacOS/jit")
        try FileManager.default.createDirectory(at: oldPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: oldPath.path,
            withDestinationPath: "../Helpers/JitPassAgent.app/Contents/MacOS/jit"
        )
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let link = bin.appendingPathComponent("jit").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: oldPath.path)
        XCTAssertEqual(CommandLineTool.state(bundled: helperJit, path: bin.path), .linked(link))
    }

    func testLinkTargetFallsBackToUsrLocalWithAdmin() {
        // Neither usual directory is on this PATH, so the answer is the
        // password path whatever the machine has installed.
        let target = CommandLineTool.linkTarget(path: "/nowhere:/else")
        XCTAssertEqual(target.directory, "/usr/local/bin")
        XCTAssertTrue(target.needsAdmin)
    }
}
