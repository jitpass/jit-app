// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The "who must not get the new-user flow" table of
/// docs/design/onboarding.md §8, one test per row the status read decides.
final class VaultSetupTests: XCTestCase {
    private func status(_ json: String) throws -> CLIStatus {
        try JSONDecoder().decode(CLIStatus.self, from: Data(json.utf8))
    }

    func testAFreshMacNeedsSetup() throws {
        let s = try status(#"{"vault":{"initialized":"no","secrets_stored":0}}"#)
        XCTAssertEqual(VaultSetup(status: s), .needsSetup)
    }

    func testAnExistingCLIUserIsReady() throws {
        let s = try status(#"{"vault":{"initialized":"yes","secrets_stored":67}}"#)
        XCTAssertEqual(VaultSetup(status: s), .ready)
    }

    func testAVaultInitialisedAndEmptyIsReadyNotNew() throws {
        let s = try status(#"{"vault":{"initialized":"yes","secrets_stored":0}}"#)
        XCTAssertEqual(VaultSetup(status: s), .ready)
    }

    /// Secrets on disk with no key is doctor's total-loss state. Offering
    /// "create a vault" over it would be the wrong answer.
    func testSecretsWithNoKeyNeedARestoreNotASetup() throws {
        let s = try status(#"{"vault":{"initialized":"no","secrets_stored":67}}"#)
        XCTAssertEqual(VaultSetup(status: s), .needsRestore)
    }

    func testAKeychainThatWillNotAnswerIsNotANewUser() throws {
        let s = try status(#"{"vault":{"initialized":"unknown","secrets_stored":0}}"#)
        XCTAssertEqual(VaultSetup(status: s), .unknown)
    }

    func testAJitBeforeTheFieldIsNotANewUser() throws {
        let s = try status(#"{"vault":{"secrets_stored":0}}"#)
        XCTAssertEqual(VaultSetup(status: s), .unknown)
    }

    func testNoStatusAtAllIsNotANewUser() {
        XCTAssertEqual(VaultSetup(status: nil), .unknown)
    }
}
