// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class VaultFailureTests: XCTestCase {
    func testASecureEnclaveRefusalReadsPlainly() {
        let said = "jit vault move-out: nothing moved: this copy of jit can't use the Secure Enclave; use the jit inside JitPass.app"
        XCTAssertTrue(VaultFailure.needsInstalledApp(said))
        XCTAssertEqual(VaultFailure.plain(said), VaultFailure.installedAppLine)
        XCTAssertEqual(VaultFailure.plain("jit vault get: secret not found"), "jit vault get: secret not found")
    }

    /// Each entry that stays says why, from jit's own result.
    func testEveryStayHasItsReason() throws {
        let json = #"{"read":5,"moved":["crm/CRM_URL"],"checks":["crm/CRM_SECRET_FILE"],"skipped":["#
            + #"{"path":"crm/CRM_REGION","reason":"a setting, left in the vault: a pointer file names it (~/w/.env.pointers)"},"#
            + #"{"path":"crm/CRM_MODE","reason":"a setting, left in the vault: no profile names it"},"#
            + #"{"path":"crm/CRM_OTHER","reason":"could not be read: permission denied"}],"dry_run":true}"#
        let r = try MigrateSettingsResult.parse(json)
        XCTAssertEqual(r.stayReason("crm/CRM_SECRET_FILE"), .looksSecret)
        XCTAssertEqual(r.stayReason("crm/CRM_REGION"), .pointerFile)
        XCTAssertEqual(r.stayReason("crm/CRM_MODE"), .noProfile)
        XCTAssertEqual(r.stayReason("crm/CRM_OTHER"), .unreadable)
        XCTAssertEqual(r.stayReason("crm/CRM_CLIENT_SECRET"), .secret)
    }
}
