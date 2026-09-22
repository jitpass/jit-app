// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The Decoys window on Meni's Mac, 2026-09-22: three protected files, eight
/// decoy reads in a week — all because the vault was locked — and one read
/// on 19 Sep that asked hibob/.env for a variable the vault does not hold.
final class DecoyReportTests: XCTestCase {
    private let home = "/Users/me"
    private let mounts = [
        CLIMount(path: "/Users/me/ops/hibob/.env", lastServe: CLIMountServe(unixTime: 1_790_089_895, decoy: true, undelivered: true)),
        CLIMount(path: "/Users/me/ops/wiz/.env"),
        CLIMount(path: "/Users/me/ops/notion/.env")
    ]

    private func event(
        _ time: Int64, _ files: [String], cause: String, count: Int? = nil, undelivered: Bool? = nil, op: String = "decoy",
        by: String? = nil
    ) -> SessionEvent {
        SessionEvent(unixTime: time, kind: "serve", op: op, by: by, cause: cause, labels: files, count: count, undelivered: undelivered)
    }

    private func secret(_ path: String, origin: String?) throws -> VaultSecret {
        var json = #"{"path":"\#(path)","version":1"#
        if let origin {
            json += #","origin":"\#(origin)""#
        }
        return try JSONDecoder().decode(VaultSecret.self, from: Data((json + "}").utf8))
    }

    private var events: [SessionEvent] {
        let locked = "the vault session is locked, so no real value is resolved"
        return [
            event(
                1_789_842_974,
                ["~/ops/hibob/.env"],
                cause: "no real value is resolved: resolving HIBOB_BASE_URL (hibob/HIBOB_BASE_URL): secret not found",
                undelivered: true
            ),
            event(1_789_985_242, ["~/ops/wiz/.env"], cause: locked, count: 2),
            event(1_789_985_242, ["~/ops/hibob/.env"], cause: locked, count: 2),
            event(1_790_072_636, ["~/ops/wiz/.env"], cause: locked),
            event(1_790_072_636, ["~/ops/notion/.env"], cause: locked),
            event(1_790_072_636, ["~/ops/hibob/.env"], cause: locked),
            event(1_789_901_151, ["~/ops/wiz/.env"], cause: "", op: "real", by: "/usr/bin/python3 sync.py")
        ]
    }

    func testFilesCarryTheirSecretsReadsAndTheMissingVariable() throws {
        let secrets = try [
            secret("hibob/HIBOB_TOKEN", origin: "~/ops/hibob/.env"),
            secret("hibob/HIBOB_URL", origin: "/Users/me/ops/hibob/.env"),
            secret("wiz/WIZ_CLIENT_SECRET", origin: "/Users/me/ops/wiz/.env"),
            secret("scratch/ONE", origin: nil)
        ]
        let report = DecoyReport.make(mounts: mounts, secrets: secrets, events: events, home: home)
        XCTAssertEqual(
            report.files.map(\.path),
            ["/Users/me/ops/hibob/.env", "/Users/me/ops/notion/.env", "/Users/me/ops/wiz/.env"],
            "the broken file first, then by path"
        )
        let hibob = report.files[0]
        XCTAssertEqual(hibob.secrets, 2, "the vault writes an origin with ~, the service lists the mount in full")
        XCTAssertEqual(hibob.lastRead, Date(timeIntervalSince1970: 1_790_089_895), "from the service, not the audit")
        XCTAssertNil(report.files[1].lastRead)
        XCTAssertEqual(hibob.decoyReads, 3, "an opened-and-nothing-read is not a read")
        XCTAssertEqual(hibob.missing, "HIBOB_BASE_URL")
        XCTAssertEqual(hibob.missingAt, Date(timeIntervalSince1970: 1_789_842_974))
        let wiz = report.files[2]
        XCTAssertEqual(wiz.decoyReads, 3)
        XCTAssertEqual(wiz.realReads, 1)
        XCTAssertEqual(wiz.lastRealRead, Date(timeIntervalSince1970: 1_789_901_151))
        XCTAssertEqual(report.broken.map(\.path), [hibob.path])
        XCTAssertEqual(report.protected.count, 2)
        XCTAssertEqual(report.secrets, 3)
    }

    func testReadsAreOneRowPerMomentAndSayWhy() {
        let report = DecoyReport.make(mounts: mounts, secrets: [], events: events, home: home)
        XCTAssertEqual(report.decoyReads, 7)
        XCTAssertEqual(report.realReads, 1)
        XCTAssertFalse(report.allWhileLocked, "one read got the real values")
        XCTAssertEqual(report.reads.count, 4, "three files at one second are one row")
        let latest = report.reads[0]
        XCTAssertEqual(latest.files.count, 3)
        XCTAssertEqual(latest.reads, 3)
        XCTAssertNil(latest.reader, "the audit did not record who")
        XCTAssertEqual(latest.why, DecoyReport.lockedWhy)
        let real = report.reads.first { $0.real }
        XCTAssertEqual(real?.reader, "python3")
        XCTAssertEqual(real?.why, "the real values, through jit")
        let nothing = report.reads.last
        XCTAssertEqual(nothing?.reads, 0)
        XCTAssertEqual(nothing?.why, "a run asked for HIBOB_BASE_URL · not in the vault · nothing was served")

        let onlyLocked = DecoyReport.make(mounts: mounts, secrets: [], events: Array(events[1 ..< 6]), home: home)
        XCTAssertTrue(onlyLocked.allWhileLocked)
        XCTAssertNil(DecoyReport.missingVariable("the vault session is locked"))
        XCTAssertEqual(DecoyReport.abbreviate("/Users/me/ops/x/.env", home: home), "~/ops/x/.env")
        XCTAssertEqual(DecoyReport.abbreviate("/etc/x", home: home), "/etc/x")
    }
}
