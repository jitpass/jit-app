// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// "A session expires, or a scheduled scan finds something new" was one
/// switch. Split in two, the scan half must not change on upgrade.
final class NotificationPreferenceTests: XCTestCase {
    func testTheSplitSwitchFollowsTheOneItCameFromUntilSet() {
        XCTAssertFalse(NotificationPreference.split(own: nil, from: false))
        XCTAssertTrue(NotificationPreference.split(own: nil, from: true))
    }

    func testOnceSetItIsItsOwn() {
        XCTAssertTrue(NotificationPreference.split(own: true, from: false))
        XCTAssertFalse(NotificationPreference.split(own: false, from: true))
    }

    func testNothingStoredIsOnLikeEveryNotificationSwitch() {
        XCTAssertTrue(NotificationPreference.split(own: nil, from: nil))
    }
}
