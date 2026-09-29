// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// Delete Profile for a profile holding plain settings: a setting is not a
/// secret, so it is named as one, by its path, and has no history to lose.
final class ProfileRmSettingsTests: XCTestCase {
    private let home = "/Users/someone"

    func testASettingIsCalledASetting() {
        let only = ProfileRmPlan(profile: "billing-sync", deleteSecrets: ["jit://setting/billing-sync/REGION"], coverageComplete: true)
        let message = only.confirmation(home: home).message
        XCTAssertTrue(message.contains("It deletes the profile and the setting nothing else uses:\nbilling-sync/REGION (setting)"), message)
        XCTAssertFalse(message.contains("secret"), message)
        XCTAssertFalse(message.contains("jit://"), message)
    }

    func testSettingsAndSecretsAreCountedApart() {
        let mixed = ProfileRmPlan(
            profile: "billing-sync", deleteSecrets: ["jit://setting/billing-sync/REGION", "billing-sync/API_KEY"], coverageComplete: true
        )
        let message = mixed.confirmation(home: home).message
        XCTAssertTrue(message.contains(
            "It deletes the profile, 1 setting and 1 secret nothing else uses, history and all:\n"
                + "billing-sync/REGION (setting)\nbilling-sync/API_KEY"
        ), message)
    }
}
