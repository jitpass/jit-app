// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class ScanScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOffIsNeverDue() {
        XCTAssertFalse(ScanSchedule.off.isDue(last: nil, now: now))
        XCTAssertFalse(ScanSchedule.off.isDue(last: now.addingTimeInterval(-1e9), now: now))
    }

    func testLaunchIsDueOnceOnly() {
        XCTAssertTrue(ScanSchedule.launch.isDue(last: nil, now: now))
        XCTAssertFalse(ScanSchedule.launch.isDue(last: now.addingTimeInterval(-1e9), now: now))
    }

    func testIntervalsAreDueAfterTheirGap() {
        for (schedule, gap) in [(ScanSchedule.hourly, 3600.0), (.daily, 86400), (.weekly, 7 * 86400), (.monthly, 30 * 86400)] {
            XCTAssertTrue(schedule.isDue(last: nil, now: now), "\(schedule) first run")
            XCTAssertFalse(schedule.isDue(last: now.addingTimeInterval(-gap + 1), now: now), "\(schedule) early")
            XCTAssertTrue(schedule.isDue(last: now.addingTimeInterval(-gap), now: now), "\(schedule) on time")
        }
    }

    func testEveryCaseHasALabelAndRoundTripsThePreference() {
        for schedule in ScanSchedule.allCases {
            XCTAssertFalse(schedule.label.isEmpty)
            XCTAssertEqual(ScanSchedule(rawValue: schedule.rawValue), schedule)
        }
        XCTAssertEqual(ScanSchedule.default, .daily)
    }
}
