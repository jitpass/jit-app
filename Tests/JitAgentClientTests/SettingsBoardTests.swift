// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The Settings window's dots: which card is amber, and which pill
/// therefore carries the dot for a card the filter is hiding.
final class SettingsBoardTests: XCTestCase {
    func testEverySegmentHoldsItsOwnGroupsAndTogetherAllOfThem() {
        let grouped = SettingsSegment.allCases.flatMap(\.groups)
        XCTAssertEqual(grouped.count, SettingsGroup.allCases.count)
        XCTAssertEqual(Set(grouped), Set(SettingsGroup.allCases))
        XCTAssertEqual(SettingsSegment.general.groups, [.general])
        XCTAssertEqual(SettingsSegment.protection.groups, [.protection])
        XCTAssertEqual(SettingsSegment.notifications.groups, [.notifications])
        XCTAssertEqual(SettingsSegment.scan.groups, [.scan, .excludes])
        XCTAssertEqual(SettingsSegment.reset.groups, [.reset])
    }

    /// The tab Settings opens on holds no button that deletes anything:
    /// emptying the vault and removing the app are Reset's alone.
    func testOnlyResetHoldsWhatDeletes() {
        for segment in SettingsSegment.allCases where segment != .reset {
            XCTAssertFalse(segment.groups.contains(.reset), segment.title)
        }
        XCTAssertEqual(SettingsSegment.allCases.map(\.title), ["General", "Protection", "Notifications", "Scan", "Reset"])
    }

    func testAQuietMacHasNoAmberCardAndNoDotOnAnyPill() {
        let facts = SettingsFacts()
        for group in SettingsGroup.allCases {
            XCTAssertNotEqual(facts.state(of: group), .needsYou, group.title)
        }
        for segment in SettingsSegment.allCases {
            XCTAssertFalse(facts.needsYou(in: segment), segment.title)
        }
    }

    func testResetAndTheSkipListAreNeverGreen() {
        let facts = SettingsFacts()
        XCTAssertEqual(facts.state(of: .reset), SettingsState.none)
        XCTAssertEqual(facts.state(of: .excludes), SettingsState.none)
    }

    func testProtectionIsRedOnlyWhenTheServiceIsDown() {
        XCTAssertEqual(SettingsFacts(serviceRunning: true).state(of: .protection), .healthy)
        XCTAssertEqual(SettingsFacts(serviceRunning: false).state(of: .protection), .broken)
        XCTAssertEqual(SettingsFacts(serviceRunning: false).worst(in: .protection), .broken)
        XCTAssertTrue(SettingsFacts(serviceRunning: false).needsYou(in: .protection))
    }

    /// A vault key nothing can open, or one every change refuses, is as
    /// red on the pill as it is on its row; a move to finish is amber.
    func testProtectionTakesTheVaultKeyRowsColour() {
        XCTAssertEqual(SettingsFacts(vaultKey: .lost).state(of: .protection), .broken)
        XCTAssertEqual(SettingsFacts(vaultKey: .restorePending).state(of: .protection), .broken)
        XCTAssertEqual(SettingsFacts(vaultKey: .changeUnknown("x")).state(of: .protection), .broken)
        XCTAssertEqual(SettingsFacts(vaultKey: .copyInKeychain).state(of: .protection), .broken)
        XCTAssertEqual(SettingsFacts(vaultKey: .unfinished(.secureEnclave)).state(of: .protection), .needsYou)
        XCTAssertEqual(SettingsFacts(vaultKey: .restoreUnchecked("x")).state(of: .protection), .needsYou)
        XCTAssertEqual(SettingsFacts(vaultKey: .secureEnclave).state(of: .protection), .healthy)
        XCTAssertEqual(SettingsFacts(vaultKey: .keychain).state(of: .protection), .healthy)
        XCTAssertEqual(SettingsFacts(vaultKey: .unfinished(.secureEnclave)).worst(in: .protection), .needsYou)
    }

    func testAPillShowsRedBeforeAmber() {
        let facts = SettingsFacts(updateAvailable: true)
        XCTAssertEqual(facts.worst(in: .general), .needsYou)
        XCTAssertNil(facts.worst(in: .reset))
    }

    /// Blocked notifications nobody asked for are not a problem the reader
    /// has to solve, so the card stays quiet until a switch is on.
    func testNotificationsAreAmberOnlyWhereTheyWereAskedFor() {
        XCTAssertEqual(
            SettingsFacts(notificationsWanted: false, notificationsBlocked: true).state(of: .notifications),
            .healthy
        )
        XCTAssertEqual(
            SettingsFacts(notificationsWanted: true, notificationsBlocked: true).state(of: .notifications),
            .needsYou
        )
        XCTAssertEqual(
            SettingsFacts(notificationsWanted: true, notificationsBlocked: false).state(of: .notifications),
            .healthy
        )
    }

    /// Full Disk Access matters to a scheduled scan, which runs with
    /// nobody there to answer the prompts.
    func testScanIsAmberOnlyWhenAScheduledScanCannotSeeEverything() {
        XCTAssertEqual(SettingsFacts(scanScheduled: false, fullDiskAccess: false).state(of: .scan), .healthy)
        XCTAssertEqual(SettingsFacts(scanScheduled: true, fullDiskAccess: false).state(of: .scan), .needsYou)
        XCTAssertEqual(SettingsFacts(scanScheduled: true, fullDiskAccess: true).state(of: .scan), .healthy)
    }

    func testGeneralIsAmberForANewReleaseOrAMissingLink() {
        XCTAssertEqual(SettingsFacts(updateAvailable: true).state(of: .general), .needsYou)
        XCTAssertEqual(SettingsFacts(jitOnPath: false).state(of: .general), .needsYou)
        XCTAssertEqual(SettingsFacts().state(of: .general), .healthy)
    }

    /// The whole point of the dot: the card is in a segment the reader is
    /// not looking at, and the pill says so without hiding anything else.
    func testAPillCarriesTheDotOfTheCardBehindIt() {
        let facts = SettingsFacts(scanScheduled: true, fullDiskAccess: false)
        XCTAssertTrue(facts.needsYou(in: .scan))
        XCTAssertFalse(facts.needsYou(in: .protection))
        XCTAssertFalse(facts.needsYou(in: .general))

        let blocked = SettingsFacts(notificationsWanted: true, notificationsBlocked: true)
        XCTAssertTrue(blocked.needsYou(in: .notifications))
        XCTAssertFalse(blocked.needsYou(in: .protection))
        XCTAssertFalse(blocked.needsYou(in: .scan))
    }

    // MARK: - Outcomes

    func testASuccessNamesTheValueAndCarriesNoOutputAtAll() {
        let outcome = SettingsOutcome.applied(.lockTimer, value: "15 minutes")
        XCTAssertTrue(outcome.ok)
        XCTAssertEqual(outcome.title, "Lock timer set to 15 minutes. jit restarted.")
        XCTAssertNil(outcome.verbatim)
        XCTAssertFalse(outcome.offersStart)
    }

    func testAServiceThatIsNotRunningIsNamedAndOffersToStart() {
        let line = "jit: service not running (no socket at ~/.jit/agent.sock)"
        let outcome = SettingsOutcome.failed(.lockTimer, line: line)
        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.title, "The lock timer did not change")
        XCTAssertEqual(outcome.detail, "jit is not running, so it kept the timer it had. Start the service and set it again.")
        XCTAssertEqual(outcome.verbatim, line)
        XCTAssertTrue(outcome.offersStart)
    }

    /// jit's words stay; a cause the line does not state is not invented
    /// over them, and no Start Service button appears for a failure the
    /// service being up would not have prevented.
    func testAnyOtherRefusalKeepsItsWordsAndClaimsNoCause() {
        let line = "jit: ttl must be between 1m and 24h"
        let outcome = SettingsOutcome.failed(.lockTimer, line: line)
        XCTAssertEqual(outcome.detail, "jit did not make the change. Its own words are below.")
        XCTAssertEqual(outcome.verbatim, line)
        XCTAssertFalse(outcome.offersStart)
    }
}
