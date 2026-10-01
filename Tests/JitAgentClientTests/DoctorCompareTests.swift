// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class DoctorCompareTests: XCTestCase {
    /// Compare used to run `jit vault duplicates` and paste its text into
    /// a sheet. The Vault window shows the same comparison as rows, so the
    /// button opens that and runs nothing itself.
    func testCompareOpensTheDuplicatesRows() throws {
        let duplicates = DoctorItem(kind: "duplicates", scope: nil, profile: nil, variable: nil, path: nil, detail: nil, action: nil)
        let action = try XCTUnwrap(DoctorAdvice.actions(for: duplicates).first)
        XCTAssertEqual(action.title, "Compare")
        XCTAssertEqual(action.opens, .duplicates)
        XCTAssertNil(action.argv, "it runs nothing")
        XCTAssertFalse(action.showsOutput, "and shows no command output")
    }
}
