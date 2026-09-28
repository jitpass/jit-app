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

    /// cobra's usage block and help hint are not jit's reason, and the
    /// header holds a sentence, not a log.
    func testTheLineStopsAtUsageAndIsCapped() {
        let usage = "jit vault prune: unknown flag: --al\nUsage:\n  jit vault prune [flags]\n\n"
            + "Flags:\n  -h, --help\nRun 'jit vault prune --help' for usage."
        XCTAssertEqual(DoctorFailureLine.make(output: usage, argv: ["vault", "prune"], status: 1), "jit vault prune: unknown flag: --al")
        let long = DoctorFailureLine.make(output: String(repeating: "word ", count: 200), argv: ["x"], status: 1)
        XCTAssertLessThanOrEqual(long.count, DoctorFailureLine.maxLength)
        XCTAssertTrue(long.hasSuffix("…"))
    }

    /// Step 1 warned about the Secure Enclave and succeeded; step 2 failed
    /// for another reason. Trying again can help, so Try Again stays.
    func testOnlyTheFailingStepDecidesWhetherToRetry() {
        let steps = [
            DoctorAction("Set", "jit vault set a/B --stdin", argv: [["vault", "set", "a/B", "--stdin"]]),
            DoctorAction("Restart", "jit service restart", argv: [["service", "restart"]])
        ]
        let button = DoctorButton("Fix", .run(steps))
        let card = DoctorCard(id: "c", tier: .broken, title: "Service", items: [DoctorItem(kind: "service", detail: "x")])
        let warned = "note: this copy of jit can't use the Secure Enclave; use the jit inside JitPass.app\n"
        let failed = "jit service restart: the service did not answer\n"
        let outcome = card.outcome(
            key: "c", button: button, completed: 1, output: warned + failed, failed: true, failedOutput: failed
        )
        XCTAssertTrue(outcome.retryable, "an earlier step's warning is not why this one failed")
        let refused = card.outcome(key: "c", button: button, completed: 1, output: warned + refusal, failed: true, failedOutput: refusal)
        XCTAssertFalse(refused.retryable)
    }
}
