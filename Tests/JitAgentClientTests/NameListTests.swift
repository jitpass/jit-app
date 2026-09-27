// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class NameListTests: XCTestCase {
    func testAShortListIsSaidInFull() {
        XCTAssertEqual(NameList.capped([]), "")
        XCTAssertEqual(NameList.capped(["ACME_KEY", "GLOBEX_TOKEN"]), "ACME_KEY, GLOBEX_TOKEN")
    }

    /// One past the limit is said in full: "and 1 more" is no shorter
    /// than the name it stands for.
    func testOnePastTheLimitIsStillSaidInFull() {
        XCTAssertEqual(NameList.capped(["A", "B", "C", "D"], limit: 3), "A, B, C, D")
    }

    func testALongListNamesTheFirstFewAndCountsTheRest() {
        let names = (1 ... 25).map { "V\($0)" }
        XCTAssertEqual(NameList.capped(names), "V1, V2, V3, V4, V5 and 20 more")
        XCTAssertEqual(NameList.capped(names, limit: 2, separator: "; "), "V1; V2 and 23 more")
    }
}
