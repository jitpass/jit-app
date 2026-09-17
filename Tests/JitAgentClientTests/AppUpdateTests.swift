// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class AppUpdateTests: XCTestCase {
    func testVersionParsesThreeAndFourParts() {
        XCTAssertEqual(AppVersion("1.6.2")?.parts, [1, 6, 2])
        XCTAssertEqual(AppVersion("v1.6.1.3")?.parts, [1, 6, 1, 3])
        XCTAssertNil(AppVersion("1.6"))
        XCTAssertNil(AppVersion("1.6.1.3.4"))
        XCTAssertNil(AppVersion("1.6.x"))
        XCTAssertNil(AppVersion(""))
    }

    func testVersionOrdersAppOnlyReleasesBelowTheNextJit() throws {
        let v1613 = try XCTUnwrap(AppVersion("1.6.1.3"))
        let v162 = try XCTUnwrap(AppVersion("1.6.2"))
        let v161 = try XCTUnwrap(AppVersion("1.6.1"))
        XCTAssertTrue(v161 < v1613)
        XCTAssertTrue(v1613 < v162)
        XCTAssertFalse(v162 < v1613)
        XCTAssertEqual(AppVersion("1.6.2"), AppVersion("1.6.2.0"))
        XCTAssertEqual("\(v1613)", "1.6.1.3")
    }

    func testRedirectLocationNamesTheVersion() {
        XCTAssertEqual(
            AppUpdate.version(fromRedirect: "https://github.com/jitpass/jit-app/releases/tag/v1.6.3")?.parts, [1, 6, 3]
        )
        XCTAssertNil(AppUpdate.version(fromRedirect: "https://github.com/jitpass/jit-app/releases"))
        XCTAssertNil(AppUpdate.version(fromRedirect: "https://evil.example/jitpass/jit-app/releases/tag/v9.9.9"))
        XCTAssertNil(AppUpdate.version(fromRedirect: "not a url at all"))
    }

    func testAvailableOnlyWhenNewerAndNotADevelopmentBuild() throws {
        let current = try XCTUnwrap(AppVersion("1.6.2"))
        XCTAssertEqual(try AppUpdate.available(current: current, latest: XCTUnwrap(AppVersion("1.6.3")))?.parts, [1, 6, 3])
        XCTAssertEqual(try AppUpdate.available(current: current, latest: XCTUnwrap(AppVersion("1.6.2.1")))?.parts, [1, 6, 2, 1])
        XCTAssertNil(AppUpdate.available(current: current, latest: current))
        XCTAssertNil(try AppUpdate.available(current: current, latest: XCTUnwrap(AppVersion("1.6.1.3"))))
        XCTAssertNil(try AppUpdate.available(current: XCTUnwrap(AppVersion("0.0.0")), latest: XCTUnwrap(AppVersion("1.6.3"))))
    }
}
