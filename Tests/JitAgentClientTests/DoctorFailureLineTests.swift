// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class DoctorFailureLineTests: XCTestCase {
    /// jit's refusal, as it printed it: wrapped over four lines. The header
    /// used to show only the last one, a bare command path.
    private let refusal = """
    jit service restart: this vault's key is in the Secure Enclave,
    and only the jit inside JitPass.app can reach it; run it from there:
    /Applications/JitPass.app/Contents/Helpers/JitPassAgent.app/Contents/
    MacOS/jit service restart
    """

    func testTheLineIsJitsWholeSentence() {
        let line = DoctorFailureLine.make(output: refusal, argv: ["service", "restart"], status: 1)
        XCTAssertTrue(line.hasPrefix("jit service restart: this vault's key is in the Secure Enclave, and only"), line)
        XCTAssertFalse(line.hasPrefix("jit service restart: jit service restart"), "named once")
        XCTAssertEqual(DoctorFailureLine.make(output: "", argv: ["vault", "prune"], status: 2), "jit vault prune: exit 2")
        XCTAssertEqual(
            DoctorFailureLine.make(output: "no such profile\n", argv: ["profile", "drop"], status: 1),
            "jit profile drop: no such profile"
        )
    }

    func testARefusalOnlyTheInstalledAppCanPassIsNotRetried() {
        XCTAssertTrue(DoctorFailureLine.needsTheInstalledApp(refusal))
        XCTAssertTrue(DoctorFailureLine
            .needsTheInstalledApp("nothing moved: this copy of jit can't use the Secure Enclave; use the jit in"))
        XCTAssertFalse(DoctorFailureLine.needsTheInstalledApp("jit service restart: the service did not answer"))
    }
}
