// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class ServiceRestartTests: XCTestCase {
    /// The menu's Service row reads Doctor: a finding whose fix is a
    /// restart says "needs restart"; a socket a sandbox blocked does not,
    /// since restarting would not change it.
    func testAServiceFindingARestartFixesIsTheOneTheMenuOffers() throws {
        let restart = #"""
        {"ok":true,"problems":[],"warnings":[
          {"kind":"service","detail":"jit's background service is running, but this shell was refused its socket.",
           "action":"a sandbox is the usual cause — allow ~/.jit/agent.sock in its config"},
          {"kind":"service",
           "detail":"The background service is running a different build than this CLI (service 2.3.1, CLI 2.3.2).",
           "action":"`jit service restart` to move it now instead of waiting",
           "fixes":[{"command":"jit service restart","argv":["service","restart"],"external":false,"destructive":false,"presence":false}]}]}
        """#
        let r = try JSONDecoder().decode(DoctorReport.self, from: Data(restart.utf8))
        XCTAssertEqual(r.serviceRestart?.detail?.hasPrefix("The background service is running a different build"), true)
        let blocked = try JSONDecoder().decode(
            DoctorReport.self,
            from: Data(restart.replacingOccurrences(of: "{\"kind\":\"service\",\n", with: "{\"kind\":\"mount_stale\",\n").utf8)
        )
        XCTAssertNil(blocked.serviceRestart, "a blocked socket is not a restart")
        XCTAssertEqual(PanelValue.service(running: true, needsRestart: true), .init("needs restart", .amber))
        XCTAssertEqual(PanelValue.service(running: false, needsRestart: true), .init("not running", .red))
    }
}
