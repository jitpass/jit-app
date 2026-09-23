// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class ProfileDiscoveryTests: XCTestCase {
    /// A home with three stores: one beside a project the registry knows,
    /// one beside a project a program is running in (found by walking up
    /// from a subfolder), and the global store. Plus a folder with no
    /// store at all, which must contribute nothing.
    private func fixture() throws -> (home: String, registry: String) {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("jitpass-discovery-\(UUID().uuidString)").path
        func write(_ path: String, _ text: String) throws {
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
            )
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        try write(
            "\(home)/Security-Ops/custom_scripts/wiz/.jit/profiles/wiz.yaml",
            "WIZ_CLIENT_ID: wiz/id\nWIZ_CLIENT_SECRET: wiz/secret\n"
        )
        try write("\(home)/Security-Ops/.jit/profiles/mcp-caido.yaml", "# caido\nCAIDO_URL: caido/url\n")
        try write("\(home)/Security-Ops/.jit/profiles/custom_scripts-jamf.yaml", "JAMF_URL: jamf/url\nJAMF_CLIENT_ID: jamf/id\n")
        try write("\(home)/.jit/profiles/global-one.yaml", "TOKEN: global/token\n")
        try FileManager.default.createDirectory(atPath: "\(home)/jitpass/src", withIntermediateDirectories: true)
        let registry = "\(home)/Library/Application Support/jitpass/mounts.yaml"
        try write(registry, """
        mounts:
            - mount_path: \(home)/Security-Ops/custom_scripts/wiz/.env
              profile_path: \(home)/Security-Ops/custom_scripts/wiz/.jit/profiles/wiz.yaml

        """)
        return (home, registry)
    }

    func testFindsProfilesFromRegistryProcessesAndHome() throws {
        let (home, registry) = try fixture()
        let found = ProfileDiscovery.discover(
            home: home, mountsRegistry: registry,
            workingDirectories: ["\(home)/Security-Ops/custom_scripts", "\(home)/jitpass/src"]
        )
        XCTAssertEqual(found.map(\.name), ["custom_scripts-jamf", "global-one", "mcp-caido", "wiz"])
        let wiz = try XCTUnwrap(found.first { $0.name == "wiz" })
        XCTAssertEqual(wiz.root, "\(home)/Security-Ops/custom_scripts/wiz", "the registry's manifest path names its project")
        XCTAssertEqual(wiz.keys, ["WIZ_CLIENT_ID", "WIZ_CLIENT_SECRET"])
        XCTAssertEqual(wiz.paths, ["wiz/id", "wiz/secret"], "the vault paths a grant would cover")
        XCTAssertEqual(wiz.missing(from: ["wiz/id"]), ["wiz/secret"], "a path the vault lacks is what the service refuses")
        XCTAssertEqual(wiz.missing(from: ["wiz/id", "wiz/secret"]), [])
        let caido = try XCTUnwrap(found.first { $0.name == "mcp-caido" })
        XCTAssertEqual(caido.root, "\(home)/Security-Ops", "a program's folder is walked up to the store above it")
        XCTAssertEqual(caido.keys, ["CAIDO_URL"], "a comment line is not a key")
        let global = try XCTUnwrap(found.first { $0.name == "global-one" })
        XCTAssertNil(global.root, "the global store has no project")
        XCTAssertEqual(global.grantProfile, GrantProfile(name: "global-one", root: nil))
    }

    func testAFolderWithNoStoreContributesNothingAndNothingIsListedTwice() throws {
        let (home, registry) = try fixture()
        let found = ProfileDiscovery.discover(
            home: home, mountsRegistry: registry,
            workingDirectories: ["\(home)/jitpass", "\(home)/Security-Ops", "\(home)/Security-Ops/custom_scripts/wiz"],
            extraRoots: ["\(home)/Security-Ops"]
        )
        XCTAssertEqual(found.map(\.name), ["custom_scripts-jamf", "global-one", "mcp-caido", "wiz"])
        XCTAssertEqual(Set(found.map(\.manifestPath)).count, found.count)
    }

    func testAnEmptyMacHasNoProfiles() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("jitpass-empty-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        XCTAssertEqual(ProfileDiscovery.discover(home: home, mountsRegistry: home + "/none.yaml", workingDirectories: [home]), [])
    }

    func testRegistryPathsAndProjectRoot() {
        XCTAssertEqual(
            ProfileDiscovery.projectRoot(ofManifest: "/Users/me/app/.jit/profiles/app.yaml"),
            "/Users/me/app"
        )
        XCTAssertEqual(
            ProfileDiscovery.ancestors(of: "/Users/me/app/src/deep", upTo: "/Users/me"),
            ["/Users/me/app/src/deep", "/Users/me/app/src", "/Users/me/app", "/Users/me"]
        )
        XCTAssertEqual(
            ProfileDiscovery.ancestors(of: "/opt/tool", upTo: "/Users/me"),
            ["/opt/tool"],
            "outside home, only the folder itself"
        )
    }
}
