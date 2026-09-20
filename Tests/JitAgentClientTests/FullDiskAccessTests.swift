// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class FullDiskAccessTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func file(_ name: String, mode: NSNumber = 0o600) throws -> String {
        let path = dir.appendingPathComponent(name).path
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8), attributes: [.posixPermissions: mode])
        return path
    }

    func testAReadableProbeIsTheGrant() throws {
        XCTAssertTrue(try FullDiskAccess.granted(probing: [file("readable")]))
    }

    /// The reported bug: macOS 27 has no per-user TCC database, so the one
    /// hardcoded path this checked could not be opened on a Mac that HAD
    /// granted access, and the menu said "needs Full Disk Access" forever.
    /// A missing candidate must hand the question to the next one. Negative
    /// control: the old single-path probe fails this, having no next one.
    func testAMissingProbeAsksTheNextOne() throws {
        let readable = try file("readable")
        XCTAssertTrue(FullDiskAccess.granted(probing: [dir.appendingPathComponent("gone").path, readable]))
    }

    /// The other half, and why "missing" cannot simply mean "granted":
    /// a refusal is an answer, and a later candidate must not overrule it.
    func testARefusalStopsTheSearch() throws {
        let refused = try file("refused", mode: 0o000)
        let readable = try file("readable")
        XCTAssertFalse(FullDiskAccess.granted(probing: [refused, readable]))
    }

    func testNoCandidateLeftSaysNo() {
        XCTAssertFalse(FullDiskAccess.granted(probing: [dir.appendingPathComponent("gone").path]))
        XCTAssertFalse(FullDiskAccess.granted(probing: []))
    }

    /// The system database is asked first because it is the one that exists
    /// on every macOS this app runs on; the per-user one is the fallback for
    /// the versions that still have it.
    func testTheSystemDatabaseIsAskedFirst() {
        XCTAssertEqual(FullDiskAccess.probes.first, "/Library/Application Support/com.apple.TCC/TCC.db")
        XCTAssertEqual(FullDiskAccess.probes.count, 2)
        XCTAssertTrue(FullDiskAccess.probes[1].hasSuffix("Library/Application Support/com.apple.TCC/TCC.db"))
        XCTAssertTrue(FullDiskAccess.probes[1].hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
    }
}
