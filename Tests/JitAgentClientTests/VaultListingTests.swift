// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class VaultListingTests: XCTestCase {
    private let json = #"""
    {"secrets":[
      {"path":"aws-prod/SECRET_ACCESS_KEY","version":4,"class":"aws","group_id":"954d","origin":"~/.clisso.yaml","updated_unix":1787041732},
      {"path":"aws-prod/ACCESS_KEY_ID","version":4,"class":"aws","group_id":"954d","origin":"~/.clisso.yaml","updated_unix":1787041732},
      {"path":"stripe/live","version":4,"class":"manual","storage":"op-ref"},
      {"path":"stripe/dev-key","version":1},
      {"path":"loose","version":2,"class":"manual","updated_unix":0}
    ],"backups":["_backups/Users/me/.aws/credentials.jit-bak-1787031214"]}
    """#

    func testDecodesHeadersAndNeverAValue() throws {
        let listing = try JSONDecoder().decode(VaultListing.self, from: Data(json.utf8))
        XCTAssertEqual(listing.secrets.count, 5)
        XCTAssertEqual(listing.backups.count, 1)
        XCTAssertEqual(listing.linkedCount, 1)
        let key = listing.secrets[0]
        XCTAssertEqual(key.group, "aws-prod")
        XCTAssertEqual(key.name, "SECRET_ACCESS_KEY")
        XCTAssertEqual(key.secretClass, "aws")
        XCTAssertNotNil(key.updated)
        XCTAssertFalse(key.isLinked)
        XCTAssertTrue(listing.secrets[2].isLinked)
        // A version-1 envelope and a zero stamp both read as "unknown", not 1970.
        XCTAssertNil(listing.secrets[3].updated)
        XCTAssertNil(listing.secrets[4].updated)
        XCTAssertEqual(listing.secrets[4].group, "loose")
        XCTAssertEqual(listing.secrets[4].name, "loose")
    }

    func testGroupsSortAndShareAnOrigin() throws {
        let listing = try JSONDecoder().decode(VaultListing.self, from: Data(json.utf8))
        let groups = listing.groups
        XCTAssertEqual(groups.map(\.name), ["aws-prod", "loose", "stripe"])
        XCTAssertEqual(groups[0].secrets.map(\.name), ["ACCESS_KEY_ID", "SECRET_ACCESS_KEY"])
        XCTAssertEqual(groups[0].origin, "~/.clisso.yaml")
        XCTAssertNil(groups[2].origin)
    }

    func testFilterMatchesGroupNameOriginOrMember() throws {
        let listing = try JSONDecoder().decode(VaultListing.self, from: Data(json.utf8))
        XCTAssertEqual(listing.groups(matching: "clisso").map(\.name), ["aws-prod"])
        XCTAssertEqual(listing.groups(matching: "clisso")[0].secrets.count, 2)
        let dev = listing.groups(matching: "DEV-key")
        XCTAssertEqual(dev.map(\.name), ["stripe"])
        XCTAssertEqual(dev[0].secrets.map(\.name), ["dev-key"])
        XCTAssertEqual(listing.groups(matching: "  ").count, 3)
        XCTAssertTrue(listing.groups(matching: "nothing-here").isEmpty)
    }

    func testFilterFindsLinksByTheWordLinked() throws {
        let listing = try JSONDecoder().decode(VaultListing.self, from: Data(json.utf8))
        for word in ["linked", "link", "1password", "1Pass"] {
            let hits = listing.groups(matching: word)
            XCTAssertEqual(hits.map(\.name), ["stripe"], word)
            XCTAssertEqual(hits.first?.secrets.map(\.name), ["live"], word)
        }
        XCTAssertTrue(listing.groups[2].hasLink)
        XCTAssertFalse(listing.groups[0].hasLink)
    }

    func testEmptyListingDecodes() throws {
        let listing = try JSONDecoder().decode(VaultListing.self, from: Data(#"{"secrets":[],"backups":[]}"#.utf8))
        XCTAssertTrue(listing.groups.isEmpty)
    }

    func testHistoryVersionsCarryTheStampRestoreTakes() throws {
        let json = #"""
        {"path":"stripe/dev-key","versions":[
          {"stamp":1787041732,"created_unix":1786000000,"updated_unix":1786500000},{"stamp":1786000000}]}
        """#
        let history = try JSONDecoder().decode(VaultHistory.self, from: Data(json.utf8))
        XCTAssertEqual(history.versions.map(\.stamp), [1_787_041_732, 1_786_000_000])
        XCTAssertEqual(history.versions[0].archived.timeIntervalSince1970, 1_787_041_732)
        XCTAssertEqual(history.versions[0].valueFrom?.timeIntervalSince1970, 1_786_500_000)
        XCTAssertNil(history.versions[1].valueFrom)
    }
}
