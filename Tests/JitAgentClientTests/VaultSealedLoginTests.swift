// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// jit #223 marks a sealed login's vault row with its store: a tool's whole
/// login, never a value to reveal, replace, restore or move out.
final class VaultSealedLoginTests: XCTestCase {
    func testASealedLoginRowCarriesItsStoreAndAnOrdinarySecretNone() throws {
        let rows = try JSONDecoder().decode([VaultSecret].self, from: Data(#"""
        [{"path":"gcloud-cli/store","version":2,"class":"gcp","store":"gcloud"},
         {"path":"azure-cli/store","version":2,"class":"azure","store":"az"},
         {"path":"aws-sso/cache","version":2,"class":"aws_signin","store":"aws-sso"},
         {"path":"aws/default/aws_secret_access_key","version":2,"class":"aws"},
         {"path":"acme/TOKEN","version":2,"class":"dotenv","store":""}]
        """#.utf8))
        XCTAssertEqual(rows.map(\.store), ["gcloud", "az", "aws-sso", nil, nil])
        XCTAssertEqual(rows.map(\.isSealedLogin), [true, true, true, false, false])
    }

    /// Never keyed on the class: an ordinary AWS key of class aws, or a
    /// gcp file, is a value like any other.
    func testTheClassAloneNeverMakesASealedLogin() throws {
        let row = try JSONDecoder().decode(VaultSecret.self, from: Data(#"{"path":"gcp/adc.json","version":2,"class":"gcp"}"#.utf8))
        XCTAssertFalse(row.isSealedLogin)
    }
}
